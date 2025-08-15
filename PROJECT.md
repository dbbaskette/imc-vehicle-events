# Project Brief: IMC Telemetry Stream (SCDF)

## 1. Project Overview & Goal

- **Primary goal**: Stream-processing pipeline in Spring Cloud Data Flow (SCDF) to detect accidents and deliver outputs to RabbitMQ and HDFS with pre-flattened JSON input.
  - Source: RabbitMQ (`telematics_exchange` with fanout distribution)
  - Processor: `imc-telemetry-processor` (detects accidents; forwards accidents only)
  - Sinks:
    - RabbitMQ sink → `vehicle_events.vehicle-events-group`
    - `imc-hdfs-sink` → write flat telemetry JSON to HDFS as Parquet
  - Demo scale: tens of events/sec; keep simple and low-latency.
  - Modules:
    - `imc-telemetry-processor`: Spring Cloud Stream processor (flat JSON in → accidents out)
    - `imc-hdfs-sink`: Spring Cloud Stream sink (flat JSON in → HDFS Parquet)

- **End users**: Internal analytics/claims platforms and real-time monitoring tools.

## 2. Tech Stack

- **Language**: Java 21
- **Frameworks**: Spring Boot 3.5.3, Spring Cloud Stream 2024.0.0 (Rabbit binder)
- **Messaging**: RabbitMQ
- **Storage**: HDFS (Parquet), Greenplum (accident events)
- **Logging**: SLF4J
- **Build**: Maven with Maven Wrapper (`./mvnw`)

## 3. Architecture & Design

- **High-Level Architecture (SCDF)**:
  - Simplified fanout: `telematics_exchange` (fanout) → both `imc-telemetry-processor` and `imc-hdfs-sink`
  - SCDF runs in Cloud Foundry; RabbitMQ is in CF; apps are registered in SCDF as processors/sinks
- **Processing**:
  - `imc-telemetry-processor`: filters flat JSON for ONLY accidents (`g_force > 5.0`) and sends to database
  - `imc-hdfs-sink`: writes ALL flat telemetry as Parquet files partitioned by date and driver
- **Data Flow**: Pre-flattened JSON eliminates transformation overhead
- **Directory Structure**:
  - `imc-telemetry-processor/`: SCDF processor app
  - `imc-hdfs-sink/`: SCDF sink app

## 4. Message Schema

- **Flat Telemetry Message Structure (optimized input)**:
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
  "driver_id": 400018,
  "gps_latitude": 33.7701,
  "gps_longitude": -84.3876,
  "gps_altitude": 351.59,
  "gps_speed": 14.5,
  "gps_bearing": 148.37,
  "gps_accuracy": 2.64,
  "gps_satellite_count": 11,
  "gps_fix_time": 150,
  "accelerometer_x": 0.1234,
  "accelerometer_y": -0.0567,
  "accelerometer_z": 0.9876,
  "gyroscope_x": 0.02,
  "gyroscope_y": -0.01,
  "gyroscope_z": 0.15,
  "magnetometer_x": 25.74,
  "magnetometer_y": -8.73,
  "magnetometer_z": 40.51,
  "magnetometer_heading": 148.37,
  "barometric_pressure": 1013.25,
  "device_battery_level": 82,
  "device_signal_strength": -63,
  "device_orientation": "portrait",
  "device_screen_on": false,
  "device_charging": true
}
```
- **Timestamp**: `event_time` is ISO 8601 with `Z` (UTC). Automatically converted to `TIMESTAMP WITH TIME ZONE` in Greenplum.
- **Performance**: Pre-flattened structure eliminates transformation overhead and provides direct database mapping.

## 5. Processing Flow

1. External telemetry generator sends pre-flattened JSON to `telematics_exchange` (fanout)
2. `telematics_exchange` distributes to both consumers:
   - `imc-hdfs-sink` (ALL messages) → HDFS Parquet partitioned by date/driver
   - `imc-telemetry-processor` (filters by `g_force > threshold`) → `vehicle_events` queue
3. JDBC sink consumes from `vehicle_events` → Greenplum database
4. Log sink taps processor output for debugging

## 6. Database Schema

Greenplum table matches flat JSON exactly:

```sql
CREATE TABLE vehicle_events (
    policy_id INTEGER,
    vehicle_id INTEGER,
    vin VARCHAR(255),
    event_time TIMESTAMP WITH TIME ZONE,
    speed_mph REAL,
    speed_limit_mph INTEGER,
    current_street VARCHAR(255),
    g_force REAL,
    driver_id INTEGER,
    -- GPS fields (gps_*)
    gps_latitude DOUBLE PRECISION,
    gps_longitude DOUBLE PRECISION,
    -- ... all sensor fields match JSON names exactly
)
DISTRIBUTED BY (vehicle_id)
PARTITION BY RANGE (event_time);
```

## 7. Coding Standards & Conventions

- Prefer readable, descriptive names; avoid abbreviations.
- Use early returns and guard clauses; avoid deep nesting.
- Do not catch exceptions without meaningful handling; log with context.
- Match existing formatting; do not reformat unrelated code.

## 8. Important Do's and Don'ts

- **DO** treat flat JSON as direct input—no transformation needed.
- **DO** maintain field names exactly as they appear in the input JSON.
- **DO NOT** modify the JSON payload—it's already optimized.
- **DO NOT** commit secrets or real credentials; use the provided config templates.

## 9. Configuration

- RabbitMQ input: exchange `telematics_exchange` (fanout)
- Consumer groups:
  - HDFS sink: `hdfs-sink-group`
  - Accident processor: `crash-detection-group`
- RabbitMQ accident output: queue `vehicle_events.vehicle-events-group`
- HDFS sink:
  - `hdfs.namenodeUri = hdfs://namenode:8020`
  - `hdfs.outputPath = /insurance-megacorp/telemetry-data-v2`
  - `hdfs.partitionPath = date + '/' + driver_id`
- JDBC sink: Greenplum connection for accident events

## 10. Versions

- Spring Boot: 3.5.3 (parent POM)
- Spring Cloud: 2024.0.0 (via BOM)
- Java: 21
- Maven Wrapper: included (`./mvnw`)

## 11. Deployment

- SCDF runs in Cloud Foundry; apps registered via imc-stream-manager
- Network: CF apps require egress to RabbitMQ, HDFS, and Greenplum endpoints
- HDFS: partition by date and driver; write as `hdfs` user
- Database: Greenplum for accident event storage

## Architecture Benefits

The simplified fanout architecture with pre-flattened JSON provides:

- **🚀 Zero Transformation Overhead**: No JSON processing required
- **⚡ Maximum Performance**: Direct consumption of optimized flat JSON
- **🔧 Simplified Architecture**: Fewer components, direct fanout pattern
- **📊 Database Ready**: Field names match database columns exactly
- **📈 Better Scalability**: Independent scaling of all consumers
- **🔍 Optimized Storage**: HDFS partitioned by date and driver for efficient queries

<!-- devplan:start -->
## Development Plan

## Phase: Telemetry Processor (Simplified)
- [X] Remove JSON flattening logic (input is already flat)
- [X] Simplified g_force filtering on flat JSON input
- [X] Configure bindings for flat JSON input and vehicle-events output
- [X] Validation: log and drop malformed payloads
- [X] Metrics: Micrometer counters for total, vehicle events, invalid
- [X] Unit tests: g_force thresholds, missing fields, malformed JSON
- [X] Integration test: end-to-end with real RabbitMQ (Testcontainers)

## Phase: HDFS Sink (Optimized)
- [X] Write flat JSON as Parquet with full schema
- [X] Partition output by date and driver_id in HDFS path
- [X] Performance tuning: configurable write buffer size, batch size
- [X] Replication factor: configurable (default 1)
- [X] Metrics: files written, bytes written, failures
- [X] Unit tests: message handling, metrics validation

## Phase: Database Integration
- [X] Create Greenplum schema matching flat JSON exactly
- [X] JDBC sink configuration for accident events
- [X] Timestamp handling: automatic ISO string to TIMESTAMP WITH TIME ZONE conversion
- [X] Monthly partitioning by event_time
- [X] Proper indexing on key fields (g_force, vehicle_id, etc.)

## Phase: Stream Configuration (Simplified)
- [X] Remove telemetry-flattener references from stream definitions
- [X] Direct fanout from telematics_exchange to both sinks
- [X] Update JDBC column mappings to match new schema
- [X] Simplified stream definitions with fewer components
- [X] Remove flattener module from parent POM

## Phase: Documentation Updates
- [X] Update README.md to reflect simplified architecture
- [X] Update PROJECT.md with new data flow and schema
- [X] Remove references to nested JSON and flattening
- [X] Document performance benefits of pre-flattened input
- [X] Update FLATTENED_SCHEMA.md with complete field list

## Phase: SCDF Integration (Updated)
- [X] Register simplified apps in SCDF (processor and sink only)
- [X] Deploy fanout streams with direct consumption
- [X] Verify status transitions and data flow
- [ ] End-to-end validation with flat JSON telemetry generator
- [ ] Performance testing with simplified architecture
<!-- devplan:end -->

## 12. Security & Observability

- Secrets via environment variables; no secret manager integration
- Standard logging; no additional metrics/JMX required
- Actuator endpoints for health and metrics monitoring

## 13. SCDF Stream Architecture (Simplified Fanout)

### **Stream Topology Overview**
The system uses a simple fanout pattern where:
- **ALL telemetry messages** → HDFS (historical storage as Parquet)
- **ONLY accident events** (g_force > 5.0) → vehicle_events queue → database

### **Simplified Fanout Architecture**

**Stream Definitions:**
```bash
# All flat telemetry → HDFS
telemetry-to-hdfs = :telematics_exchange > imc-hdfs-sink

# Flat telemetry → accident filter → database
telemetry-to-processor = :telematics_exchange > imc-telemetry-processor > :vehicle_events
vehicle-events-to-jdbc = :vehicle_events > vehicle-events-sink: jdbc

# Debug tap
vehicle-events-to-log = :telemetry-to-processor.imc-telemetry-processor > log
```

**Benefits:**
- Direct fanout from exchange to consumers
- No transformation overhead
- Independent scaling of all consumers
- Simple to understand and maintain
- Maximum performance with pre-flattened JSON

**Configuration:**
- HDFS sink: `group=hdfs-sink-group`
- Telemetry processor: `group=crash-detection-group`
- Both consume from `telematics_exchange` (fanout)

## 14. Future Work

- Additional sink types (e.g., Elasticsearch for full-text search)
- Enhanced metrics and monitoring dashboards
- Real-time alerting based on accident patterns
- Machine learning integration for predictive analytics