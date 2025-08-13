#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

# Cleanup handler
PROC_PID=""
cleanup() {
  set +e
  if [ -n "${PROC_PID:-}" ]; then
    # Kill process group to terminate mvn/java children
    kill -TERM -"$PROC_PID" 2>/dev/null || true
    kill -TERM "$PROC_PID" 2>/dev/null || true
    sleep 1
    kill -KILL -"$PROC_PID" 2>/dev/null || true
    kill -KILL "$PROC_PID" 2>/dev/null || true
  fi
  docker rm -f imc-rabbit >/dev/null 2>&1 || true
  set -e
}
trap cleanup INT TERM EXIT

echo "Starting RabbitMQ..."
docker run -d --rm --name imc-rabbit -p 5672:5672 -p 15672:15672 rabbitmq:3.13-management >/dev/null

echo "Waiting for RabbitMQ..."
for i in {1..30}; do curl -fsS http://localhost:15672 >/dev/null 2>&1 && break; sleep 2; done

echo "Declaring queues..."
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest declare queue name=telematics_work_queue.crash-detection-group durable=true || true
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest declare queue name=vehicle-events.vehicle-events-group durable=true || true

echo "Building processor..."
./mvnw -q -DskipTests -pl imc-telemetry-processor -am package

echo "Preparing app config..."
PROC_RES=imc-telemetry-processor/src/main/resources
cp "$PROC_RES"/application.yml.template "$PROC_RES"/application.yml
sed -i.bak "s#telematics_work_queue#telematics_work_queue.crash-detection-group#" "$PROC_RES"/application.yml

echo "Running processor..."
JAR=imc-telemetry-processor/target/imc-telemetry-processor-1.0.0-SNAPSHOT.jar
java -jar "$JAR" &
PROC_PID=$!

echo "Waiting for processor health..."
for i in {1..30}; do curl -fsS http://localhost:8080/actuator/health >/dev/null 2>&1 && break; sleep 2; done

echo "Publishing sample messages..."
SAMPLE_OK='{"g_force":1.2,"policy_id":1,"vehicle_id":2}'
SAMPLE_EVT='{"g_force":6.5,"policy_id":1,"vehicle_id":2, "sensors":{"gps":{"latitude":33.7,"longitude":-84.38}}}'
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest publish routing_key=telematics_work_queue.crash-detection-group payload="$SAMPLE_OK"
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest publish routing_key=telematics_work_queue.crash-detection-group payload="$SAMPLE_EVT"

echo "Checking vehicle-events queue..."
docker exec imc-rabbit rabbitmqadmin --username=guest --password=guest get queue=vehicle-events.vehicle-events-group ackmode=ack_requeue_false count=10 || true

echo "Query actuator metrics..."
curl -fsS http://localhost:8080/actuator/metrics/telemetry_messages_total || true
curl -fsS http://localhost:8080/actuator/metrics/telemetry_vehicle_events_total || true
curl -fsS http://localhost:8080/actuator/metrics/telemetry_invalid_messages_total || true

echo "Done (CTRL-C not required; script will clean up)"

