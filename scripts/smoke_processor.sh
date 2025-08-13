#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

# Cleanup handler
PROC_PID=""
cleanup() {
  set +e
  if [ -n "${PROC_PID:-}" ]; then
    # Kill mvn spring-boot:run and its child
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

echo "Starting RabbitMQ..."
docker run -d --name imc-rabbit -p 5672:5672 -p 15672:15672 rabbitmq:3.13-management >/dev/null

echo "Waiting for RabbitMQ..."
for i in {1..30}; do curl -fsS http://localhost:15672 >/dev/null 2>&1 && break; sleep 2; done

echo "Resolving names from application.yml..."
APP_YML="imc-telemetry-processor/src/main/resources/application.yml"

extract_value() {
  # $1: which block (in|out), $2: key (destination|group)
  local block=$1 key=$2 flag=0 line val
  while IFS= read -r line; do
    [[ $line =~ vehicleEventsOut-${block}-0: ]] && flag=1 && continue
    [[ $flag -eq 1 && $line =~ vehicleEventsOut-(out|in)-0: ]] && break
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

INPUT_EXCHANGE=$(extract_value in destination)
INPUT_GROUP=$(extract_value in group)
OUTPUT_EXCHANGE=$(extract_value out destination)
OUTPUT_GROUP=${VEHICLE_EVENTS_GROUP:-vehicle-events-group}

INPUT_QUEUE="${INPUT_EXCHANGE}.${INPUT_GROUP}"
OUTPUT_QUEUE="${OUTPUT_EXCHANGE}.${OUTPUT_GROUP}"

echo "Declaring exchanges and queues..."
# Clean up any conflicting pre-existing resources
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest delete exchange name=vehicle_events >/dev/null 2>&1 || true
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest delete exchange name="${OUTPUT_EXCHANGE}" >/dev/null 2>&1 || true
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest delete queue name="${INPUT_QUEUE}" >/dev/null 2>&1 || true

# Input exchange only (binder will declare the consumer queue with DLQ settings)
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest declare exchange name="${INPUT_EXCHANGE}" type=direct durable=true || true

# Output exchange + a test consumer queue for verification
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest declare exchange name="${OUTPUT_EXCHANGE}" type=topic durable=true || true
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest declare queue name="${OUTPUT_QUEUE}" durable=true || true
# Bind with catch-all routing key so any publisher routing key matches
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest declare binding source="${OUTPUT_EXCHANGE}" destination_type=queue destination="${OUTPUT_QUEUE}" routing_key="#" || true

echo "Building processor..."
./mvnw -q -DskipTests -pl imc-telemetry-processor -am package

echo "Running processor..."
JAR=$(ls -1 imc-telemetry-processor/target/imc-telemetry-processor-*.jar 2>/dev/null | head -n 1 || true)
if [ -z "$JAR" ]; then
  echo "ERROR: Processor JAR not found in imc-telemetry-processor/target" >&2
  exit 1
fi
java -jar "$JAR" &
PROC_PID=$!

echo "Waiting for processor health..."
for i in {1..30}; do curl -fsS http://localhost:8080/actuator/health >/dev/null 2>&1 && break; sleep 2; done

echo "Waiting for binder to declare queues..."
sleep 3

echo "Current RabbitMQ queues:"
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest list queues name | grep -E "(telematics|vehicle)" || echo "No relevant queues found"

echo "Current bindings:"
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest list bindings source destination | grep -E "(telematics|vehicle)" || echo "No relevant bindings found"

echo "Ensuring input exchange binding..."
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest declare binding source="${INPUT_EXCHANGE}" destination_type=queue destination="${INPUT_QUEUE}" routing_key="${INPUT_QUEUE}" || true

echo "Publishing sample messages..."
SAMPLE_OK='{"g_force":1.2,"policy_id":1,"vehicle_id":2}'
SAMPLE_EVT='{"g_force":6.5,"policy_id":1,"vehicle_id":2, "sensors":{"gps":{"latitude":33.7,"longitude":-84.38}}}'
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest publish exchange="${INPUT_EXCHANGE}" routing_key="${INPUT_QUEUE}" payload="$SAMPLE_OK"
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest publish exchange="${INPUT_EXCHANGE}" routing_key="${INPUT_QUEUE}" payload="$SAMPLE_EVT"

# Wait up to 10s for publisher to emit and Rabbit to settle
TARGET_Q="${OUTPUT_QUEUE}"
echo "Waiting for messages in ${TARGET_Q} (up to 10s)..."
for i in {1..10}; do
  COUNT=$(docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest --format=tsv list queues name messages | awk -F '\t' -v q="$TARGET_Q" '$1==q {print $2}')
  if [ -n "${COUNT:-}" ] && [ "${COUNT}" -ge 1 ] 2>/dev/null; then
    echo "Messages present: ${COUNT}"
    break
  fi
  sleep 1
done

echo "Listing queue message counts (non-consuming)..."
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest list queues name messages | grep -E "(telematics|vehicle)" || true

echo "Query actuator metrics..."
curl -fsS http://localhost:8080/actuator/metrics/telemetry_messages_total || true
curl -fsS http://localhost:8080/actuator/metrics/telemetry_vehicle_events_total || true
curl -fsS http://localhost:8080/actuator/metrics/telemetry_invalid_messages_total >/dev/null 2>&1 || true

# Graceful shutdown: stop app (by mvn pid and port 8080) then Rabbit
if [ -n "${PROC_PID:-}" ]; then
  kill -TERM "$PROC_PID" 2>/dev/null || true
fi
# Also try killing the Java process bound to 8080 if still running
APP_PID=$(lsof -ti tcp:8080 2>/dev/null || true)
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
sleep "$PAUSE_SECS"
docker stop imc-rabbit >/dev/null 2>&1 || true

echo "Done"

