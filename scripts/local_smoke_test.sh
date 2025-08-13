#!/bin/bash
set -euo pipefail

# Requires: docker compose (RabbitMQ), Maven, Java, and nc (optional check)

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

echo "Starting local RabbitMQ via docker-compose..."
docker compose up -d rabbitmq

echo "Waiting for RabbitMQ to be healthy..."
for i in {1..30}; do
  if curl -sSf http://localhost:15672 >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "Declaring queues via rabbitmqadmin..."
docker exec imc-rabbitmq rabbitmqadmin --username=guest --password=guest declare queue name=telematics_work_queue durable=true || true
docker exec imc-rabbitmq rabbitmqadmin --username=guest --password=guest declare queue name=telematics_raw_for_spark durable=true || true
docker exec imc-rabbitmq rabbitmqadmin --username=guest --password=guest declare queue name=telematics_work_queue.crash-detection-group durable=true || true
docker exec imc-rabbitmq rabbitmqadmin --username=guest --password=guest declare queue name=vehicle-events.vehicle-events-group durable=true || true

echo "Publishing 2 sample messages to telematics_work_queue..."
SAMPLE1='{"policy_id":200018,"vehicle_id":300021,"vin":"1HGBH41JXMN109186","timestamp":"2024-01-15T10:30:45.123Z","speed_mph":32.5,"g_force":1.18,"sensors":{"gps":{"latitude":33.7701,"longitude":-84.3876},"magnetometer":{"heading":148.37}}}'
SAMPLE2='{"policy_id":200019,"vehicle_id":300022,"vin":"1HGBH41JXMN109187","timestamp":"2024-01-15T10:35:45.123Z","speed_mph":42.5,"g_force":6.2,"sensors":{"gps":{"latitude":33.7701,"longitude":-84.3876},"magnetometer":{"heading":148.37}}}'

docker exec imc-rabbitmq rabbitmqadmin --username=guest --password=guest publish routing_key=telematics_work_queue.crash-detection-group payload="$SAMPLE1"
docker exec imc-rabbitmq rabbitmqadmin --username=guest --password=guest publish routing_key=telematics_work_queue.crash-detection-group payload="$SAMPLE2"

echo "Building project..."
./mvnw -q -DskipTests package

echo "Running connector (forwards to telematics_raw_for_spark)..."
(cd imc-rabbit-spark-connector && ../mvnw -q spring-boot:run -Dspring-boot.run.jvmArguments="-DRABBITMQ_HOST=localhost -DRABBITMQ_PORT=5672 -Dspring.cloud.stream.bindings.consumeRawTelematics-in-0.group=crash-detection-group" &)
CONNECTOR_PID=$!
sleep 5

echo "Running Spark processor (local) with test config..."
CONF=imc-spark-processor/src/main/resources/spark-processor.conf
cp imc-spark-processor/src/main/resources/spark-processor.conf.template "$CONF"
sed -i.bak "s#spark://your-spark-master:7077#local\[*\]#" "$CONF"
sed -i.bak "s#amqp://<username>:<password>@<rabbit-host>:5672/<vhost>#amqp://guest:guest@localhost:5672/%2F#" "$CONF"
sed -i.bak "s#<gp-host>#localhost#g" "$CONF"
sed -i.bak "s#<database>#postgres#g" "$CONF"
sed -i.bak "s#/insurance-megacorp/telemetry-data-v2#/insurance-megacorp/telemetry-test#g" "$CONF"

echo "Starting Spark job (runs until Ctrl+C) ..."
java -cp imc-spark-processor/target/imc-spark-processor-1.0.0-SNAPSHOT.jar com.insurancemegacorp.spark.TelematicsSparkApp &
SPARK_PID=$!

echo "Tail connector logs for a bit..."
sleep 10

echo "Check vehicle-events queue has at least 1 message (accident case)..."
docker exec imc-rabbitmq rabbitmqadmin --username=guest --password=guest get queue=vehicle-events.vehicle-events-group requeue=false count=10 || true

echo "Stop processes (leaving Rabbit running)"
kill $SPARK_PID || true
kill $CONNECTOR_PID || true

echo "Done. Review HDFS path /insurance-megacorp/telemetry-test for parquet output if HDFS is available."

