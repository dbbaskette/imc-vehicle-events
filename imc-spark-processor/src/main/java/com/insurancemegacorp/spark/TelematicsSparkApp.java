package com.insurancemegacorp.spark;

import com.fasterxml.jackson.databind.JsonNode;
import com.rabbitmq.client.*;
import org.apache.spark.sql.Dataset;
import org.apache.spark.sql.Row;
import org.apache.spark.sql.RowFactory;
import org.apache.spark.sql.SparkSession;
import org.apache.spark.sql.functions;
import org.apache.spark.sql.streaming.Trigger;
import org.apache.spark.sql.Encoders;
import org.apache.spark.api.java.function.MapFunction;
import org.apache.spark.sql.types.DataTypes;
import org.apache.spark.sql.types.Metadata;
import org.apache.spark.sql.types.StructField;
import org.apache.spark.sql.types.StructType;

import java.io.FileInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.Properties;

public class TelematicsSparkApp {

    public static void main(String[] args) throws Exception {
        Properties conf = loadConfig();

        SparkSession spark = SparkSession.builder()
                .appName("imc-spark-processor")
                .master(conf.getProperty("spark.master", "local[*]"))
                .getOrCreate();

        String rabbitUri = conf.getProperty("rabbit.uri");
        String inputQueue = conf.getProperty("rabbit.inputQueue", "telematics_raw_for_spark");
        String vehicleEventsQueue = conf.getProperty("rabbit.vehicleEventsQueue", "vehicle-events");
        String vehicleEventsGroup = conf.getProperty("rabbit.vehicleEventsGroup", "vehicle-events-group");

        String hdfsUri = conf.getProperty("hdfs.namenodeUri");
        String outputPath = conf.getProperty("hdfs.outputPath", "/insurance-megacorp/telemetry-data-v2");

        String gpUrl = conf.getProperty("greenplum.url");
        String gpUser = conf.getProperty("greenplum.user");
        String gpPassword = conf.getProperty("greenplum.password");
        String gpTable = conf.getProperty("greenplum.table");

        int triggerMs = Integer.parseInt(conf.getProperty("processing.triggerMs", "2000"));

        // Define a canonical schema for key flattened fields (flexible: we still carry raw JSON)
        StructType schema = new StructType(new StructField[]{
                new StructField("policy_id", DataTypes.LongType, true, Metadata.empty()),
                new StructField("vehicle_id", DataTypes.LongType, true, Metadata.empty()),
                new StructField("vin", DataTypes.StringType, true, Metadata.empty()),
                new StructField("timestamp", DataTypes.TimestampType, true, Metadata.empty()),
                new StructField("speed_mph", DataTypes.DoubleType, true, Metadata.empty()),
                new StructField("g_force", DataTypes.DoubleType, true, Metadata.empty()),
                new StructField("latitude", DataTypes.DoubleType, true, Metadata.empty()),
                new StructField("longitude", DataTypes.DoubleType, true, Metadata.empty()),
                new StructField("heading", DataTypes.DoubleType, true, Metadata.empty()),
                new StructField("raw_json", DataTypes.StringType, false, Metadata.empty())
        });

        // Ingestion: Start an in-memory queue that feeds Spark via a custom MicroBatch reader
        StreamingQueue streamingQueue = new StreamingQueue();
        startRabbitConsumerToQueue(rabbitUri, inputQueue, streamingQueue);

        Dataset<Row> raw = spark.readStream()
                .format("rate") // dummy source to drive micro-batches
                .option("rowsPerSecond", 1)
                .load()
                .map((MapFunction<Row, String>) row -> streamingQueue.poll(), Encoders.STRING())
                .toDF("value");

        // Extract flattened fields from JSON using get_json_object to avoid custom encoders
        Dataset<Row> flattened = raw.select(
                functions.get_json_object(functions.col("value"), "$.policy_id").cast("long").alias("policy_id"),
                functions.get_json_object(functions.col("value"), "$.vehicle_id").cast("long").alias("vehicle_id"),
                functions.get_json_object(functions.col("value"), "$.vin").alias("vin"),
                functions.to_timestamp(
                        functions.get_json_object(functions.col("value"), "$.timestamp"),
                        "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
                ).alias("timestamp"),
                functions.get_json_object(functions.col("value"), "$.speed_mph").cast("double").alias("speed_mph"),
                functions.get_json_object(functions.col("value"), "$.g_force").cast("double").alias("g_force"),
                functions.get_json_object(functions.col("value"), "$.sensors.gps.latitude").cast("double").alias("latitude"),
                functions.get_json_object(functions.col("value"), "$.sensors.gps.longitude").cast("double").alias("longitude"),
                functions.get_json_object(functions.col("value"), "$.sensors.magnetometer.heading").cast("double").alias("heading"),
                functions.col("value").alias("raw_json")
        );

        // Write all flattened records to HDFS as Parquet (partitioned by date only)
        Dataset<Row> withDate = flattened.withColumn("date", functions.to_date(functions.col("timestamp")));
        withDate.writeStream()
                .format("parquet")
                .option("path", outputPath + "/date=__HIVE_DEFAULT_PARTITION__")
                .option("checkpointLocation", outputPath + "/_checkpoint")
                .trigger(Trigger.ProcessingTime(triggerMs))
                .start();

        // Accidents: g_force > 5.0 → write to GP and publish to Rabbit vehicle-events
        withDate.filter(functions.col("g_force").gt(5.0))
                .writeStream()
                .foreachBatch((batch, batchId) -> {
                    batch.persist();
                    batch.foreachPartition(iter -> {
                        try (Connection conn = gpUrl != null ? DriverManager.getConnection(gpUrl, gpUser, gpPassword) : null;
                             com.rabbitmq.client.Connection amqpConn = createRabbitConnection(rabbitUri);
                             Channel channel = amqpConn != null ? amqpConn.createChannel() : null) {
                            PreparedStatement ps = null;
                            if (conn != null && gpTable != null && !gpTable.isBlank()) {
                                conn.setAutoCommit(false);
                                String sql = "INSERT INTO " + gpTable + " (policy_id, vehicle_id, vin, ts, speed_mph, g_force, latitude, longitude, heading) VALUES (?,?,?,?,?,?,?,?,?)";
                                ps = conn.prepareStatement(sql);
                            }
                            while (iter.hasNext()) {
                                Row r = iter.next();
                                // Greenplum write
                                if (ps != null) {
                                    ps.setObject(1, r.getAs("policy_id"));
                                    ps.setObject(2, r.getAs("vehicle_id"));
                                    ps.setString(3, r.getAs("vin"));
                                    ps.setTimestamp(4, r.getAs("timestamp"));
                                    ps.setObject(5, r.getAs("speed_mph"));
                                    ps.setObject(6, r.getAs("g_force"));
                                    ps.setObject(7, r.getAs("latitude"));
                                    ps.setObject(8, r.getAs("longitude"));
                                    ps.setObject(9, r.getAs("heading"));
                                    ps.addBatch();
                                }
                                // Publish accidents to Rabbit
                                if (channel != null) {
                                    String json = r.getAs("raw_json");
                                    // Default exchange with routingKey = queue name
                                    channel.basicPublish("", vehicleEventsQueue, null, json.getBytes(StandardCharsets.UTF_8));
                                }
                            }
                            if (ps != null) {
                                ps.executeBatch();
                                conn.commit();
                                ps.close();
                            }
                        }
                    });
                    batch.unpersist();
                })
                .start();

        spark.streams().awaitAnyTermination();
    }

    private static Properties loadConfig() throws IOException {
        Properties p = new Properties();
        try (FileInputStream fis = new FileInputStream("imc-spark-processor/src/main/resources/spark-processor.conf")) {
            p.load(fis);
        }
        return p;
    }

    private static void startRabbitConsumerToQueue(String rabbitUri, String inputQueue, StreamingQueue queue) throws Exception {
        Thread t = new Thread(() -> {
            ConnectionFactory factory = new ConnectionFactory();
            try {
                factory.setUri(rabbitUri);
                try (com.rabbitmq.client.Connection conn = factory.newConnection();
                     Channel channel = conn.createChannel()) {
                    channel.basicQos(100);
                    channel.queueDeclare(inputQueue, true, false, false, null);
                    DeliverCallback deliverCallback = (consumerTag, delivery) -> {
                        String message = new String(delivery.getBody(), StandardCharsets.UTF_8);
                        queue.offer(message);
                        channel.basicAck(delivery.getEnvelope().getDeliveryTag(), false);
                    };
                    channel.basicConsume(inputQueue, false, deliverCallback, consumerTag -> {});
                    // Keep thread alive
                    // no-op loop
                    while (true) {
                        Thread.sleep(1000);
                    }
                }
            } catch (Exception e) {
                e.printStackTrace();
            }
        }, "rabbit-consumer-thread");
        t.setDaemon(true);
        t.start();
    }

    private static com.rabbitmq.client.Connection createRabbitConnection(String rabbitUri) throws Exception {
        if (rabbitUri == null || rabbitUri.isBlank()) return null;
        ConnectionFactory factory = new ConnectionFactory();
        factory.setUri(rabbitUri);
        return factory.newConnection();
    }

    private static String getText(JsonNode node, String field) { return node.has(field) && !node.get(field).isNull() ? node.get(field).asText() : null; }
    private static Double getDouble(JsonNode node, String field) { return node.has(field) && !node.get(field).isNull() ? node.get(field).asDouble() : null; }
    private static Long getLong(JsonNode node, String field) { return node.has(field) && !node.get(field).isNull() ? node.get(field).asLong() : null; }
}


