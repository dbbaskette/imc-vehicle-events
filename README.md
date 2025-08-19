<div align="center">
  <img src="assets/logo.png" alt="Insurance MegaCorp Logo" width="200"/>
</div>

# IMC Telemetry Stream (SCDF)

Multi-module project containing:
- `imc-telemetry-processor`: Spring Cloud Stream processor that filters flattened telemetry for accidents (g_force > threshold).
- `imc-hdfs-sink`: Spring Cloud Stream sink that writes flattened telemetry JSON to HDFS as Parquet (partitioned by date and driver).
- `imc-jdbc-consumer`: Custom JDBC consumer with Prometheus metrics and service registry integration for enhanced monitoring.
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
# Configure TELEMETRY_INPUT_EXCHANGE (flat JSON), VEHICLE_EVENTS_OUTPUT_EXCHANGE, VEHICLE_EVENT_GFORCE_THRESHOLD
```

HDFS Sink:
```bash
cd imc-hdfs-sink/src/main/resources
cp application.yml.template application.yml
# Configure HDFS_NAMENODE_URI and HDFS_OUTPUT_PATH
```

JDBC Consumer:
```bash
cd imc-jdbc-consumer/src/main/resources
cp application.yml.template application.yml
# Configure DATABASE_URL, DATABASE_USERNAME, DATABASE_PASSWORD, TABLE_NAME
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
#    - Telemetry Streams (simplified fanout architecture) 
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

The system implements a **simplified fanout architecture** with pre-flattened JSON input for optimal performance:

#### HDFS Storage Stream: `telemetry-to-hdfs`
```bash
# All flattened telemetry data goes directly to HDFS for archival
:telematics_exchange > imc-hdfs-sink
```

#### Accident Detection Stream: `telemetry-to-processor`
```bash
# Flattened data is processed for accident detection and sent to database
:telematics_exchange > imc-telemetry-processor > :vehicle_events
```

#### Database Storage Stream: `vehicle-events-to-jdbc`
```bash
# Vehicle events (accidents) are stored in the database with enhanced monitoring
:vehicle_events > imc-jdbc-consumer
```

#### Debug Stream: `vehicle-events-to-log`
```bash
# A tap on the processor's output sends accident data to log for debugging
:telemetry-to-processor.imc-telemetry-processor > log
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
           ↓ (pre-flattened JSON)
      telematics_exchange (fanout)
           ├─────────────────────┐
           ↓                     ↓
    ┌─────────────────┐   ┌─────────────────┐
    │ imc-hdfs-sink   │   │ imc-telemetry-  │ → :vehicle_events
    │ (all data)      │   │ processor       │     ↓
    │ → HDFS Parquet  │   │ (accidents only)│     ├─────────────────┐
    └─────────────────┘   └─────────────────┘     ↓                 ↓ (tap)
                                           ┌─────────────────┐ ┌─────────────────┐
                                           │ imc-jdbc-       │ │ Log Sink        │
                                           │ consumer        │ │ (debugging)     │
                                           │ (database +     │ │                 │
                                           │  metrics)       │ │                 │
                                           └─────────────────┘ └─────────────────┘
```

## HDFS Storage

### File Format and Structure
The `imc-hdfs-sink` writes all flat telemetry data to HDFS for long-term storage and analytics:

- **Format**: Apache Parquet with SNAPPY compression and **columnar schema** (35 structured fields)
- **Schema**: Structured Parquet columns instead of raw JSON for optimal analytics performance
  - Direct column access (no JSON parsing required)
  - Proper data types: `int64`, `double`, `boolean`, `UTF8`
  - Example columns: `policy_id`, `vehicle_id`, `g_force`, `gps_latitude`, `device_battery_level`
- **Parallel Writers**: 3 concurrent writers per instance for 3x file creation activity
  - Writer naming: `telemetry-timestamp-instanceId-writerId-millis.parquet`
  - Example: `telemetry-20250815_154231-cf-0-writer-A-1755272551646.parquet`
- **Partitioning**: Date-only partitioning for demo (simplified from date+driver)
  - Path structure: `/insurance-megacorp/telemetry-data-v2/date=YYYY-MM-DD/`
  - Configuration: `hdfs.partitionPath: "'date=' + T(java.time.LocalDate).now().toString()"`
- **File Rolling**: 
  - Size-based: 128MB file size limit
  - Time-based: 5-minute intervals (300 seconds)
  - Message-based: 1000 messages per batch
- **Replication**: HDFS replication factor set to 1 (demo environment)
- **Schema**: Direct mapping from flat JSON to Parquet columns (no transformation)

### Performance Benefits
- **Columnar Storage**: Parquet format optimized for analytical queries
- **Efficient Compression**: SNAPPY compression reduces storage footprint
- **Partition Pruning**: Hive-style date/driver partitioning enables efficient query filtering
- **Parallel Processing**: Multiple files enable parallel data processing
- **Zero Schema Evolution**: Flat structure eliminates nested field complexity

## Message Format

### Input: Pre-Flattened Telemetry JSON
The telemetry generator now sends optimized flat JSON directly, eliminating transformation overhead:

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

**See [FLATTENED_SCHEMA.md](FLATTENED_SCHEMA.md) for complete field mapping documentation.**

## Custom JDBC Consumer

### Enhanced Database Integration
The `imc-jdbc-consumer` provides production-grade database integration with comprehensive monitoring and service discovery:

#### Key Features
- **Prometheus Metrics**: 5 comprehensive metrics for production monitoring
  - `jdbc_consumer_messages_total` - Total messages processed by table
  - `jdbc_consumer_messages_success` - Successfully processed messages  
  - `jdbc_consumer_messages_error` - Failed messages with error classification
  - `jdbc_consumer_message_duration` - Processing time per message (histogram)
  - `jdbc_consumer_null_parameters_total` - Data quality metrics
- **Service Registry**: Eureka client integration for Cloud Foundry service discovery
- **Enhanced Error Handling**: Configurable retry logic with exponential backoff
- **Batch Processing**: Optimized throughput with configurable batch sizes (1-1000)
- **Rich Monitoring**: Comprehensive actuator endpoints including database health

#### Configuration Highlights
```yaml
# Enhanced Features
jdbc.consumer.enable-metrics: true
jdbc.consumer.metrics-prefix: "jdbc_consumer"  
jdbc.consumer.enable-retry: true
jdbc.consumer.max-retry-attempts: 3
jdbc.consumer.batch-size: 10
jdbc.consumer.idle-timeout: 5000

# Monitoring Endpoints
management.endpoints.web.exposure.include: "health,metrics,prometheus,datasource"
management.metrics.export.prometheus.enabled: true
```

#### Advantages Over Standard JDBC Sink
| Feature | Standard JDBC Sink | Custom JDBC Consumer |
|---------|-------------------|---------------------|
| **Metrics** | Basic health only | 5 comprehensive Prometheus metrics |
| **Service Discovery** | None | Eureka integration for CF |
| **Error Handling** | Basic retry | Advanced retry with classification |
| **Monitoring** | Limited endpoints | Rich actuator endpoints |
| **Batch Processing** | Fixed batching | Configurable batch size & timeout |
| **Data Quality** | No tracking | Null parameter tracking |
| **Performance Insights** | None | Duration histograms & throughput |

#### Monitoring Endpoints
- **Health Check**: `/actuator/health` (includes database connection status)
- **Prometheus Metrics**: `/actuator/prometheus` (all custom metrics)
- **Application Info**: `/actuator/info` (build info, Git commit)
- **Database Health**: `/actuator/health/db` (connection pool status)

## Database Schema

The Greenplum table schema matches the flattened JSON exactly. **Note**: Partitioning was removed to simplify the demo environment:

```sql
CREATE TABLE vehicle_events (
    -- Core vehicle data
    policy_id INTEGER,
    vehicle_id INTEGER,
    vin VARCHAR(255),
    event_time BIGINT,                    -- Unix epoch timestamp
    speed_mph REAL,
    speed_limit_mph INTEGER,
    current_street VARCHAR(255),
    g_force REAL,
    driver_id INTEGER,
    
    -- GPS data fields (gps_*)
    gps_latitude DOUBLE PRECISION,
    gps_longitude DOUBLE PRECISION,
    gps_altitude REAL,
    gps_speed REAL,
    gps_bearing REAL,
    gps_accuracy REAL,
    gps_satellite_count INTEGER,
    gps_fix_time INTEGER,
    
    -- Sensor data fields
    accelerometer_x REAL,
    accelerometer_y REAL,
    accelerometer_z REAL,
    gyroscope_x REAL,
    gyroscope_y REAL,
    gyroscope_z REAL,
    magnetometer_x REAL,
    magnetometer_y REAL,
    magnetometer_z REAL,
    magnetometer_heading REAL,
    barometric_pressure REAL,
    
    -- Device data fields (device_*)
    device_battery_level INTEGER,
    device_signal_strength INTEGER,
    device_orientation VARCHAR(255),
    device_screen_on BOOLEAN,
    device_charging BOOLEAN
)
WITH (
    APPENDONLY=true,
    OIDS=FALSE
)
DISTRIBUTED BY (vehicle_id);

-- Indexes for performance
CREATE INDEX idx_vehicle_events_event_time ON vehicle_events (event_time);
CREATE INDEX idx_vehicle_events_policy_id ON vehicle_events (policy_id);
CREATE INDEX idx_vehicle_events_vehicle_id ON vehicle_events (vehicle_id);
CREATE INDEX idx_vehicle_events_driver_id ON vehicle_events (driver_id);
CREATE INDEX idx_vehicle_events_g_force ON vehicle_events (g_force);
```

### Schema Features
- **Direct Field Mapping**: Column names match JSON field names exactly
- **Unix Timestamps**: `event_time` stored as `BIGINT` (Unix epoch) to match JSON format
- **Simplified Design**: No partitioning for demo environment (keeps it simple)
- **Performance Indexes**: Key fields indexed for efficient queries
- **Accident Focus**: Only stores high g-force events (accidents) from telemetry processor
- **Data Type Compatibility**: All types match the incoming JSON data format exactly

## Actuator Metrics

All apps expose actuator endpoints (health, info, metrics). Example queries:

### Telemetry Processor Metrics
- List metrics: `GET /actuator/metrics`
- Messages processed: `GET /actuator/metrics/telemetry_messages_total`
- Vehicle events (accidents): `GET /actuator/metrics/telemetry_vehicle_events_total`
- Invalid messages: `GET /actuator/metrics/telemetry_invalid_messages_total`

### Custom JDBC Consumer Metrics
- **Throughput**: `GET /actuator/metrics/jdbc_consumer_messages_total`
- **Success Rate**: `GET /actuator/metrics/jdbc_consumer_messages_success`
- **Error Classification**: `GET /actuator/metrics/jdbc_consumer_messages_error`
- **Processing Duration**: `GET /actuator/metrics/jdbc_consumer_message_duration`
- **Data Quality**: `GET /actuator/metrics/jdbc_consumer_null_parameters_total`
- **Database Health**: `GET /actuator/health/db`
- **Prometheus Export**: `GET /actuator/prometheus`

### Prometheus Query Examples
```promql
# Messages per second by table
rate(jdbc_consumer_messages_total[5m])

# Error rate percentage  
rate(jdbc_consumer_messages_error[5m]) / rate(jdbc_consumer_messages_total[5m]) * 100

# Processing duration 95th percentile
histogram_quantile(0.95, rate(jdbc_consumer_message_duration_bucket[5m]))
```

## Configuration Templates

- Telemetry processor: `imc-telemetry-processor/src/main/resources/application.yml.template`
- HDFS sink: `imc-hdfs-sink/src/main/resources/application.yml.template`
- JDBC consumer: `imc-jdbc-consumer/src/main/resources/application.yml.template`
- Stream manager: 
  - `imc-stream-manager/config.yml` - Global SCDF and environment settings
  - `imc-stream-manager/stream-configs/telemetry-streams.yml` - Complete telemetry processing streams configuration

## Architecture Benefits

The simplified fanout architecture with pre-flattened JSON provides:

- **🚀 Zero Transformation Overhead**: No JSON processing or flattening required
- **⚡ Maximum Performance**: Direct consumption of optimized flat JSON
- **🔧 Simplified Maintainability**: Fewer components and processing steps
- **📊 Database Ready**: Field names match database columns exactly
- **📈 Better Scalability**: Independent scaling of HDFS sink and accident processor
- **🔍 Columnar HDFS Storage**: Structured Parquet with 35 typed columns for 10-100x faster analytics
- **⚡ Parallel Writers**: 3 concurrent writers per instance for maximum demo file creation activity  
- **🗃️ Simplified Database**: No partitioning, Unix timestamps for direct JSON compatibility
- **📊 Production Monitoring**: Custom JDBC consumer with 5 Prometheus metrics for comprehensive observability
- **☁️ Cloud Native**: Service registry integration for Cloud Foundry deployments
- **🛡️ Enhanced Reliability**: Advanced error handling, retry logic, and data quality tracking

The stream manager uses a unified configuration approach with global settings in `config.yml` and stream-specific settings in the `stream-configs/` directory.