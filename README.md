# IMC Telemetry Stream (SCDF)

Multi-module project containing:
- `imc-telemetry-processor`: Spring Cloud Stream processor that taps telemetry, flattens JSON, and emits vehicle events to `vehicle-events`.
- `imc-hdfs-sink`: Spring Cloud Stream sink that writes telemetry JSON to HDFS as Parquet (partitioned by date).
- `imc-stream-manager`: SCDF stream manager scripts and configs.

## Prerequisites

- Java 21
- Maven 3.6+
- RabbitMQ (for local development)

## App Templates

Telemetry Processor:
```bash
cd imc-telemetry-processor/src/main/resources
cp application.yml.template application.yml
# Configure TELEMETRY_INPUT_QUEUE, TELEMETRY_INPUT_GROUP, VEHICLE_EVENTS_OUTPUT_QUEUE, VEHICLE_EVENT_GFORCE_THRESHOLD
```

HDFS Sink:
```bash
cd imc-hdfs-sink/src/main/resources
cp application.yml.template application.yml
# Configure HDFS_NAMENODE_URI and HDFS_OUTPUT_PATH
```

### Local RabbitMQ (docker-compose)

```bash
docker compose up -d rabbitmq
# UI: http://localhost:15672 (guest/guest)
```

### Build the Applications

```bash
# Using Maven wrapper (recommended)
./mvnw clean package

# Or using system Maven
mvn clean package
```

## Stream Manager

```bash
cd imc-stream-manager
cp scdf-config.yaml.template scdf-config.yml  # or use global config.yml and per-stream configs
# Edit SCDF endpoints and app GitHub URLs

# Interactive manager
bash stream-manager.sh

# Non-interactive
NO_PROMPT=true TOKEN=... bash stream-manager.sh
```

## Message Format

Enhanced telemetry message structure (source: `imc-telematics-gen`):

```json
{
  "policy_id": 200018,
  "vehicle_id": 300021,
  "vin": "1HGBH41JXMN109186",
  "timestamp": "2024-01-15T10:30:45.123Z",
  "speed_mph": 32.5,
  "current_street": "Peachtree Street",
  "g_force": 1.18,
  "sensors": {
    "gps": {
      "latitude": 33.7701,
      "longitude": -84.3876,
      "altitude": 351.59,
      "speed_ms": 14.5,
      "bearing": 148.37,
      "accuracy": 2.64,
      "satellite_count": 11,
      "gps_fix_time": 150
    },
    "accelerometer": {
      "x": 0.1234,
      "y": -0.0567,
      "z": 0.9876
    },
    "gyroscope": {
      "pitch": 0.02,
      "roll": -0.01,
      "yaw": 0.15
    },
    "magnetometer": {
      "x": 25.74,
      "y": -8.73,
      "z": 40.51,
      "heading": 148.37
    },
    "barometric_pressure": 1013.25,
    "device": {
      "battery_level": 82.0,
      "signal_strength": -63,
      "orientation": "portrait",
      "screen_on": false,
      "charging": true
    }
  }
}
```

## Actuator Metrics

Both apps expose actuator endpoints (health, info, metrics). Example queries:

- List metrics: `GET /actuator/metrics`
- Tapped message count: `GET /actuator/metrics/telemetry_messages_total`
- Vehicle events count: `GET /actuator/metrics/telemetry_vehicle_events_total`
- Invalid messages count: `GET /actuator/metrics/telemetry_invalid_messages_total`

## Configuration Templates

- Telemetry processor: `imc-telemetry-processor/src/main/resources/application.yml.template`
- HDFS sink: `imc-hdfs-sink/src/main/resources/application.yml.template`
- Stream manager: `imc-stream-manager/scdf-config.yaml.template` (copy to `config.yml` and create per-stream `config-<name>.yml` as needed)

These templates use environment variables for sensitive configuration values. The actual `*.yml` files are ignored by git to prevent accidentally committing secrets.