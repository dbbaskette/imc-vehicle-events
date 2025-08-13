# IMC Rabbit + Spark Suite

Multi-module project containing:
- `imc-rabbit-spark-connector`: Spring Cloud Stream Rabbit connector that consumes raw telemetry JSON.
- `imc-spark-processor`: Spark processor (stub) for flattening and analytics.

## Connector Responsibilities

- Consume raw telemetry JSON from RabbitMQ queue `telematics_work_queue` (group `crash-detection-group`).
- Do not transform/process payloads; Spark will handle flattening and analytics.
- Provide basic DLQ and consumer settings via templates.

## Prerequisites

- Java 21
- Maven 3.6+
- RabbitMQ (for local development)

## Connector Properties

Templates live in `imc-rabbit-spark-connector/src/main/resources/`:

```bash
cd imc-rabbit-spark-connector/src/main/resources
cp application.yml.template application.yml
cp application-cloud.yml.template application-cloud.yml
cp application-tunnel.yml.template application-tunnel.yml
```
Adjust `RABBITMQ_*` env vars and binding names as needed.

### Local RabbitMQ (docker-compose)

```bash
docker compose up -d rabbitmq
# UI: http://localhost:15672 (guest/guest)
```

### 2. Build the Application

```bash
# Using Maven wrapper (recommended)
./mvnw clean package

# Or using system Maven
mvn clean package
```

## Building

From the repo root:

```bash
./mvnw -q -DskipTests package
```

## Running the Connector

### Local Development
```bash
cd imc-rabbit-spark-connector
../mvnw spring-boot:run
```

### With Cloud Profile
```bash
cd imc-rabbit-spark-connector
../mvnw spring-boot:run -Dspring-boot.run.profiles=cloud
```

### With Tunnel Profile
```bash
cd imc-rabbit-spark-connector
../mvnw spring-boot:run -Dspring-boot.run.profiles=tunnel
```

### Cloud Foundry Deployment
```bash
./mvnw clean package
cf push -f manifest.yml
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

## Spark Processor

- Stub module `imc-spark-processor` targets Java 17; implement Structured Streaming to flatten and process the raw JSON.

## Configuration Templates

The application uses template files for configuration:

- `application.yml.template` - Local development with environment variable defaults
- `application-cloud.yml.template` - Cloud Foundry deployment configuration
- `application-tunnel.yml.template` - SSH tunnel configuration for development

These templates use environment variables for sensitive configuration values. The actual `application*.yml` files are ignored by git to prevent accidentally committing secrets.