# IMC Telemetry Stream (SCDF)

Multi-module project containing:
- `imc-telemetry-flattener`: Spring Cloud Stream processor that flattens nested telemetry JSON to improve performance and maintainability.
- `imc-telemetry-processor`: Spring Cloud Stream processor that processes flattened telemetry and emits vehicle events for accidents (g_force > threshold).
- `imc-hdfs-sink`: Spring Cloud Stream sink that writes flattened telemetry JSON to HDFS as Parquet (partitioned by date and driver).
- `imc-stream-manager`: SCDF stream manager scripts and configs.

## Prerequisites

- Java 21
- Maven 3.6+
- RabbitMQ (for local development)

## App Templates

Telemetry Flattener:
```bash
cd imc-telemetry-flattener/src/main/resources
cp application.yml.template application.yml
# Configure TELEMETRY_INPUT_EXCHANGE, FLATTENED_TELEMETRY_OUTPUT_EXCHANGE
```

Telemetry Processor:
```bash
cd imc-telemetry-processor/src/main/resources
cp application.yml.template application.yml
# Configure TELEMETRY_INPUT_EXCHANGE (flattened), VEHICLE_EVENTS_OUTPUT_EXCHANGE, VEHICLE_EVENT_GFORCE_THRESHOLD
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

The system implements a **dedicated flattener architecture** for improved performance and maintainability:

#### Flattening Stream: `telemetry-to-flattener`
```bash
# Raw nested JSON is flattened by the dedicated flattener service
:telematics_exchange > imc-telemetry-flattener > :flattened_telemetry_exchange
```

#### HDFS Storage Stream: `flattened-to-hdfs`
```bash
# All flattened telemetry data goes to HDFS for archival
:flattened_telemetry_exchange > imc-hdfs-sink
```

#### Accident Detection Stream: `flattened-to-processor`
```bash
# Flattened data is processed for accident detection and sent to database
:flattened_telemetry_exchange > imc-telemetry-processor > :vehicle_events
```

#### Database Storage Stream: `vehicle-events-to-jdbc`
```bash
# Vehicle events (accidents) are stored in the database
:vehicle_events > vehicle-events-sink: jdbc
```

#### Debug Stream: `vehicle-events-to-log`
```bash
# A tap on the processor's output sends accident data to log for debugging
:flattened-to-processor.imc-telemetry-processor > log
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
   # Create streams and deploy using the stream-manager.sh script
   # The script will read the definitions from stream-configs/telemetry-streams.yml
   # and deploy all streams in one operation.
   ```

3. **Deploy Streams**:
   ```bash
   # Use the stream-manager.sh script to deploy the streams.
   # Select option 5) Deploy Streams
   ```

4. **Monitor**:
   - **SCDF UI**: Stream status, metrics, logs
   - **RabbitMQ UI**: Queue depths, message rates  
   - **Actuator Endpoints**: Application health and custom metrics

### Data Flow

```
External Telemetry Generator
           ↓ (raw nested JSON)
      telematics_exchange
           ↓
   ┌─────────────────────┐
   │ imc-telemetry-      │
   │ flattener           │
   │ (dedicated service) │
   └─────────────────────┘
           ↓ (flattened JSON)
  flattened_telemetry_exchange (fanout)
           ├─────────────────────┐
           ↓                     ↓
    ┌─────────────────┐   ┌─────────────────┐
    │ imc-hdfs-sink   │   │ imc-telemetry-  │ → :vehicle_events
    │ (all data)      │   │ processor       │
    │                 │   │ (accidents only)│
    └─────────────────┘   └─────────────────┘
                                 ↓
                          ┌─────────────────┐
                          │ JDBC Sink       │
                          │ (database)      │
                          └─────────────────┘
                                 ↓ (tap)
                          ┌─────────────────┐
                          │ Log Sink        │
                          │ (debugging)     │
                          └─────────────────┘
```

## Message Format

### Input: Nested Telemetry JSON
Enhanced telemetry message structure received from external generators:

```json
{
  "policy_id": 200018,
  "vehicle_id": 300021,
  "vin": "1HGBH41JXMN109186",
  "event_time": "2024-01-15T10:30:45.123Z",
  "speed_mph": 32.5,
  "speed_limit_mph": 35,
  "current_street": "Peachtree Street",
  "g_force": 1.18,
  "driver_id": "DRIVER-400018",
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

### Output: Flattened Telemetry JSON
Flattened structure with contextual field names produced by `imc-telemetry-flattener`:

```json
{
  "policy_id": 200018,
  "vehicle_id": 300021,
  "vin": "1HGBH41JXMN109186",
  "event_time": "2024-01-15T10:30:45.123Z",
  "speed_mph": 32.5,
  "speed_limit_mph": 35,
  "current_street": "Peachtree Street",
  "g_force": 1.18,
  "driver_id": "DRIVER-400018",
  "gps_latitude": 33.7701,
  "gps_longitude": -84.3876,
  "gps_altitude": 351.59,
  "gps_speed_ms": 14.5,
  "gps_bearing": 148.37,
  "gps_accuracy": 2.64,
  "gps_satellite_count": 11,
  "gps_fix_time": 150,
  "accelerometer_x": 0.1234,
  "accelerometer_y": -0.0567,
  "accelerometer_z": 0.9876,
  "gyroscope_pitch": 0.02,
  "gyroscope_roll": -0.01,
  "gyroscope_yaw": 0.15,
  "magnetometer_x": 25.74,
  "magnetometer_y": -8.73,
  "magnetometer_z": 40.51,
  "magnetometer_heading": 148.37,
  "sensors_barometric_pressure": 1013.25,
  "device_battery_level": 82.0,
  "device_signal_strength": -63,
  "device_orientation": "portrait",
  "device_screen_on": false,
  "device_charging": true
}
```

**See [FLATTENED_SCHEMA.md](FLATTENED_SCHEMA.md) for complete field mapping documentation.**

## Actuator Metrics

All apps expose actuator endpoints (health, info, metrics). Example queries:

### Telemetry Flattener Metrics
- List metrics: `GET /actuator/metrics`
- Messages processed: `GET /actuator/metrics/telemetry_messages_total`
- Successfully flattened: `GET /actuator/metrics/telemetry_flattened_total`
- Flattening errors: `GET /actuator/metrics/telemetry_flatten_errors_total`

### Telemetry Processor Metrics
- List metrics: `GET /actuator/metrics`
- Messages processed: `GET /actuator/metrics/telemetry_messages_total`
- Vehicle events (accidents): `GET /actuator/metrics/telemetry_vehicle_events_total`
- Invalid messages: `GET /actuator/metrics/telemetry_invalid_messages_total`

## Configuration Templates

- Telemetry flattener: `imc-telemetry-flattener/src/main/resources/application.yml`
- Telemetry processor: `imc-telemetry-processor/src/main/resources/application.yml.template`
- HDFS sink: `imc-hdfs-sink/src/main/resources/application.yml.template`
- Stream manager: 
  - `imc-stream-manager/config.yml` - Global SCDF and environment settings
  - `imc-stream-manager/stream-configs/telemetry-streams.yml` - Complete telemetry processing streams configuration

## Architecture Benefits

The dedicated flattener service architecture provides:

- **🚀 Performance**: HDFS writes no longer blocked by accident detection logic
- **🔧 Maintainability**: Single flattening implementation eliminates code duplication
- **📝 Clarity**: Contextual field names (e.g., `gps_latitude`, `device_battery_level`) preserve meaning
- **⚡ Scalability**: Independent scaling of flattener, HDFS sink, and accident processor
- **🔍 Database Friendly**: Self-documenting column names improve query readability

The stream manager uses a unified configuration approach with global settings in `config.yml` and stream-specific settings in the `stream-configs/` directory.