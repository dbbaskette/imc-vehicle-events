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

### Configuration Structure

**`config.yml`** - Global SCDF settings + environment defaults
- SCDF server URL and OAuth endpoints  
- Default HDFS and version settings
- Shared across all stream operations
- RabbitMQ auto-configured by Cloud Foundry service bindings

**`stream-configs/`** - Directory containing stream-specific configurations
- `telemetry-streams.yml` - Telemetry processing streams configuration
- Each file contains app definitions, stream definitions, and deployment properties
- Follows SCDF-RAG pattern with comprehensive deployment settings

### Usage

```bash
cd imc-stream-manager

# Edit global settings
vi config.yml

# Interactive manager
bash stream-manager.sh

# Menu options:
# 1) Register default apps (global)
# 2) Create a new stream config
#    - Telemetry Streams (tap-based architecture) 
#    - Custom Stream
# 3) List configured streams  
# 4) Manage an existing stream
# 5) Deploy Streams (general deployment from stream-configs/)
# 6) Register custom app by GitHub URL

# Non-interactive mode
NO_PROMPT=true TOKEN=... bash stream-manager.sh
```

## SCDF Integration

### Stream Architecture

The system implements a **tap-based architecture** for efficient telemetry processing:

#### Main Stream: `telemetry-to-hdfs`
```bash
# All telemetry data flows to HDFS for long-term storage
rabbit --queues=telematics_work_queue --groups=crash-detection-group | imc-hdfs-sink
```

#### Tap Stream: `accident-detection`  
```bash
# Only accident events (g_force > threshold) flow to vehicle-events queue
:telemetry-to-hdfs.rabbit > imc-telemetry-processor | rabbit --queues=vehicle_events --groups=vehicle-events-group
```

### Deployment Steps

1. **Register Applications**:
   ```bash
   cd imc-stream-manager
   ./stream-manager.sh
   # Select: Register Applications → Custom GitHub Apps
   ```

2. **Create Streams**:
   ```bash
   # Create main storage stream
   stream create telemetry-to-hdfs --definition "rabbit --queues=telematics_work_queue --groups=crash-detection-group | imc-hdfs-sink"
   
   # Create accident detection tap
   stream create accident-detection --definition ":telemetry-to-hdfs.rabbit > imc-telemetry-processor | rabbit --queues=vehicle_events --groups=vehicle-events-group"
   ```

3. **Deploy Streams**:
   ```bash
   stream deploy telemetry-to-hdfs
   stream deploy accident-detection
   ```

4. **Monitor**:
   - **SCDF UI**: Stream status, metrics, logs
   - **RabbitMQ UI**: Queue depths, message rates  
   - **Actuator Endpoints**: Application health and custom metrics

### Data Flow

```
External Telemetry Generator
           ↓
   telematics_work_queue
           ↓
    ┌─────────────────┐
    │ Main Stream     │ → HDFS (all telemetry)
    │ telemetry-to-   │
    │ hdfs            │
    └─────────────────┘
           ↓ (tap)
    ┌─────────────────┐
    │ Tap Stream      │ → vehicle_events (accidents only)
    │ accident-       │
    │ detection       │
    └─────────────────┘
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
- Stream manager: 
  - `imc-stream-manager/config.yml` - Global SCDF and environment settings
  - `imc-stream-manager/config-<streamname>.yml` - Stream-specific configurations

The stream manager uses a unified configuration approach with global settings in `config.yml` and stream-specific settings in `config-<streamname>.yml` files.