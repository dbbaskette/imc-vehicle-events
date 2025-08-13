package com.insurancemegacorp.hdfssink;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.Path;
import org.apache.parquet.hadoop.ParquetWriter;
import org.apache.parquet.hadoop.metadata.CompressionCodecName;
import org.apache.parquet.schema.MessageType;
import org.apache.parquet.schema.MessageTypeParser;
import org.apache.parquet.hadoop.example.GroupWriteSupport;
import org.apache.parquet.example.data.Group;
import org.apache.parquet.example.data.simple.SimpleGroup;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;

import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.function.Consumer;

@Component
public class HdfsSink {
    private static final Logger log = LoggerFactory.getLogger(HdfsSink.class);

    @Value("${hdfs.namenodeUri:hdfs://namenode:8020}")
    private String namenodeUri;

    @Value("${hdfs.outputPath:/insurance-megacorp/telemetry-data-v2}")
    private String outputPath;

    @Bean
    public Consumer<byte[]> writeToHdfs() {
        return payload -> {
            try {
                // Define a minimal Parquet schema capturing raw JSON
                String schemaString = "message telemetry { required binary raw_json (UTF8); }";
                MessageType schema = MessageTypeParser.parseMessageType(schemaString);
                Configuration conf = new Configuration();
                GroupWriteSupport.setSchema(schema, conf);

                String date = LocalDate.now().toString();
                Path dir = new Path(outputPath + "/date=" + date);
                Path file = new Path(dir, "telemetry-" + System.currentTimeMillis() + ".parquet");

                try (ParquetWriter<Group> writer = org.apache.parquet.hadoop.example.ExampleParquetWriter.builder(file)
                        .withConf(conf)
                        .withCompressionCodec(CompressionCodecName.SNAPPY)
                        .withWriteMode(org.apache.parquet.hadoop.ParquetFileWriter.Mode.CREATE)
                        .withType(schema)
                        .build()) {
                    Group group = new SimpleGroup(schema);
                    group.add("raw_json", new String(payload));
                    writer.write(group);
                }
                log.info("Wrote telemetry parquet to {}", file);
            } catch (Exception e) {
                log.error("Failed to write Parquet to HDFS", e);
            }
        };
    }
}


