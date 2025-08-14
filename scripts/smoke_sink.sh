#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

# Cleanup handler
PROC_PID=""
cleanup() {
  set +e
  if [ -n "${PROC_PID:-}" ]; then
    # Kill java process and its children
    kill -TERM "$PROC_PID" 2>/dev/null || true
    sleep 1
    pkill -P "$PROC_PID" 2>/dev/null || true
    # Wait up to 10s for app exit
    for i in {1..10}; do
      ps -p "$PROC_PID" >/dev/null 2>&1 || break
      sleep 1
    done
  fi
  docker stop imc-rabbit >/dev/null 2>&1 || true
  docker rm -f imc-rabbit >/dev/null 2>&1 || true
  set -e
}
trap cleanup INT TERM EXIT

echo "Setting up test environment..."

echo "Starting RabbitMQ..."
docker run -d --name imc-rabbit -p 5672:5672 -p 15672:15672 rabbitmq:3.13-management >/dev/null

echo "Waiting for RabbitMQ..."
for i in {1..30}; do curl -fsS http://localhost:15672 >/dev/null 2>&1 && break; sleep 2; done

echo "Resolving configuration from application-test.yml..."
APP_YML="imc-hdfs-sink/src/main/resources/application-test.yml"

extract_value() {
  # $1: key to extract
  local key=$1 flag=0 line val
  while IFS= read -r line; do
    [[ $line =~ writeToHdfs-in-0: ]] && flag=1 && continue
    [[ $flag -eq 1 && $line =~ rabbit: ]] && break
    if [[ $flag -eq 1 && $line =~ ^[[:space:]]*$key: ]]; then
      val=${line#*:}
      val=${val//\"/}
      val=$(echo "$val" | xargs)
      # Expand ${VAR:default} to default
      if [[ $val =~ \$\{[^:}]+:([^}]+)\} ]]; then
        val=${BASH_REMATCH[1]}
      fi
      echo "$val"
      return 0
    fi
  done < "$APP_YML"
}

INPUT_EXCHANGE=$(extract_value destination)
INPUT_GROUP=$(extract_value group)
INPUT_QUEUE="${INPUT_EXCHANGE}.${INPUT_GROUP}"

echo "Configuration:"
echo "  Exchange: $INPUT_EXCHANGE"
echo "  Group: $INPUT_GROUP" 
echo "  Queue: $INPUT_QUEUE"
echo "  HDFS Path: hdfs://big-data-005.kuhn-labs.com:8020/insurance-megacorp/telemetry-smoke-test"
echo "  HDFS User: hdfs"

echo "Declaring exchanges and queues..."
# Clean up any conflicting pre-existing resources
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest delete exchange name="${INPUT_EXCHANGE}" >/dev/null 2>&1 || true
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest delete queue name="${INPUT_QUEUE}" >/dev/null 2>&1 || true

# Input exchange only (binder will declare the consumer queue with DLQ settings)
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest declare exchange name="${INPUT_EXCHANGE}" type=direct durable=true || true

echo "Building HDFS sink..."
./mvnw -q -DskipTests -pl imc-hdfs-sink -am package

echo "Running HDFS sink with test profile..."
JAR=$(ls -1 imc-hdfs-sink/target/imc-hdfs-sink-*.jar 2>/dev/null | head -n 1 || true)
if [ -z "$JAR" ]; then
  echo "ERROR: HDFS sink JAR not found in imc-hdfs-sink/target" >&2
  exit 1
fi

# Run with test profile
java -jar "$JAR" --spring.profiles.active=test &
PROC_PID=$!

echo "Waiting for HDFS sink health..."
for i in {1..30}; do curl -fsS http://localhost:8081/actuator/health >/dev/null 2>&1 && break; sleep 2; done

echo "Waiting for binder to declare queues..."
sleep 3

echo "Current RabbitMQ queues:"
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest list queues name | grep -E "(telematics|hdfs)" || echo "No relevant queues found"

echo "Ensuring input exchange binding..."
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest declare binding source="${INPUT_EXCHANGE}" destination_type=queue destination="${INPUT_QUEUE}" routing_key="${INPUT_QUEUE}" || true

echo "Publishing sample telemetry messages..."
SAMPLE_1='{"policy_id":200018,"vehicle_id":300021,"vin":"1HGBH41JXMN109186","timestamp":"2024-01-15T10:30:45.123Z","speed_mph":32.5,"current_street":"Peachtree Street","g_force":1.18,"sensors":{"gps":{"latitude":33.7701,"longitude":-84.3876}}}'
SAMPLE_2='{"policy_id":200019,"vehicle_id":300022,"vin":"2HGBH41JXMN109187","timestamp":"2024-01-15T10:31:45.123Z","speed_mph":45.2,"current_street":"Main Street","g_force":2.34,"sensors":{"gps":{"latitude":33.7702,"longitude":-84.3877}}}'
SAMPLE_3='{"policy_id":200020,"vehicle_id":300023,"vin":"3HGBH41JXMN109188","timestamp":"2024-01-15T10:32:45.123Z","speed_mph":15.8,"current_street":"Oak Avenue","g_force":0.95,"sensors":{"gps":{"latitude":33.7703,"longitude":-84.3878}}}'

# Publish messages
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest publish exchange="${INPUT_EXCHANGE}" routing_key="${INPUT_QUEUE}" payload="$SAMPLE_1"
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest publish exchange="${INPUT_EXCHANGE}" routing_key="${INPUT_QUEUE}" payload="$SAMPLE_2"
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest publish exchange="${INPUT_EXCHANGE}" routing_key="${INPUT_QUEUE}" payload="$SAMPLE_3"

echo "Waiting for batch processing (up to 15s)..."
sleep 15

echo "Checking queue consumption..."
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest list queues name messages | grep -E "(telematics|hdfs)" || true

echo "Checking HDFS sink metrics..."
curl -fsS http://localhost:8081/actuator/metrics/hdfs_messages_received_total || echo "Metric not available"
curl -fsS http://localhost:8081/actuator/metrics/hdfs_messages_written_total || echo "Metric not available"  
curl -fsS http://localhost:8081/actuator/metrics/hdfs_files_created_total || echo "Metric not available"

echo "Checking for HDFS file creation (via metrics)..."
echo "Files should be written to: hdfs://big-data-005.kuhn-labs.com:8020/insurance-megacorp/telemetry-smoke-test/"
echo "Note: Check HDFS directly for actual file verification"

echo "Publishing a few more messages to trigger file rolling..."
for i in {4..8}; do
  SAMPLE='{"policy_id":'$((200020+i))',"vehicle_id":'$((300023+i))',"vin":"'$i'HGBH41JXMN109188","timestamp":"2024-01-15T10:3'$i':45.123Z","g_force":1.5}'
  docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest publish exchange="${INPUT_EXCHANGE}" routing_key="${INPUT_QUEUE}" payload="$SAMPLE"
done

echo "Waiting for file rolling (up to 15s)..."
sleep 15

echo "Final HDFS metrics check..."

echo "Final metrics check..."
curl -fsS http://localhost:8081/actuator/metrics/hdfs_messages_received_total || echo "Metric not available"
curl -fsS http://localhost:8081/actuator/metrics/hdfs_files_created_total || echo "Metric not available"

# Graceful shutdown
if [ -n "${PROC_PID:-}" ]; then
  kill -TERM "$PROC_PID" 2>/dev/null || true
fi

# Also try killing the Java process bound to 8081 if still running
APP_PID=$(lsof -ti tcp:8081 2>/dev/null || true)
if [ -n "${APP_PID:-}" ]; then
  kill -TERM $APP_PID 2>/dev/null || true
fi

for i in {1..10}; do
  ps -p "${APP_PID:-0}" >/dev/null 2>&1 || break
  sleep 1
done

# Leave RabbitMQ up briefly for UI inspection
PAUSE_SECS=${RABBIT_PAUSE_SECONDS:-10}
echo "RabbitMQ UI available for ${PAUSE_SECS}s at http://localhost:15672 (guest/guest) ..."
echo "Generated files in: hdfs://big-data-005.kuhn-labs.com:8020/insurance-megacorp/telemetry-smoke-test/"
sleep "$PAUSE_SECS"

docker stop imc-rabbit >/dev/null 2>&1 || true

echo "Test complete!"
echo "Check HDFS for generated Parquet files at: hdfs://big-data-005.kuhn-labs.com:8020/insurance-megacorp/telemetry-smoke-test/"
echo "Files should be partitioned by date: /date=YYYY-MM-DD/telemetry-*.parquet"