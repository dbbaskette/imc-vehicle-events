# Project Brief: IMC Telemetry Stream (SCDF)

## 1. Project Overview & Goal

- **Primary goal**: Stream-processing pipeline in Spring Cloud Data Flow (SCDF) to detect accidents and deliver outputs to RabbitMQ and HDFS.
  - Source: RabbitMQ (reads `telematics_work_queue.crash-detection-group`)
  - Processor: `imc-telemetry-processor` (detects accidents; forwards accidents only)
  - Sinks:
    - RabbitMQ sink → `vehicle-events.vehicle-events-group`
    - `imc-hdfs-sink` → write telemetry JSON lines to HDFS
  - Demo scale: tens of events/sec; keep simple and low-latency.
  - Modules:
    - `imc-telemetry-processor`: Spring Cloud Stream processor (Rabbit in → accidents out)
    - `imc-hdfs-sink`: Spring Cloud Stream sink (Rabbit in → HDFS append)



- **End users**: Internal analytics/claims platforms and real-time monitoring tools.

## 2. Tech Stack

- **Language**: Java 21
- **Frameworks**: Spring Boot 3.5.3, Spring Cloud Stream 2024.0.0 (Rabbit binder)
- **Messaging**: RabbitMQ
- **Storage**: HDFS (Parquet)
- **Logging**: SLF4J
- **Build**: Maven with Maven Wrapper (`./mvnw`)

## 3. Architecture & Design

- **High-Level Architecture (SCDF)**:
  - Stream: rabbit (source) → `imc-telemetry-processor` → rabbit sink (vehicle-events) and `imc-hdfs-sink`
  - SCDF runs in Cloud Foundry; RabbitMQ is in CF; apps are registered in SCDF as processors/sinks
- **Processing**:
  - `imc-telemetry-processor`: forwards ALL telemetry to HDFS branch; emits ONLY accidents (`g_force > 5.0`) to vehicle-events branch
  - `imc-hdfs-sink`: writes inbound telemetry as Parquet files partitioned by date
- **Backward compatibility**: Enhanced schema preferred; legacy fields tolerated by processor when computing `g_force`
- **Directory Structure**:
  - `imc-telemetry-processor/`: SCDF processor app
  - `imc-hdfs-sink/`: SCDF sink app

## 4. Message Schema

- **Enhanced Telemetry Message Structure (authoritative)**:
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
    "accelerometer": { "x": 0.1234, "y": -0.0567, "z": 0.9876 },
    "gyroscope": { "pitch": 0.02, "roll": -0.01, "yaw": 0.15 },
    "magnetometer": { "x": 25.74, "y": -8.73, "z": 40.51, "heading": 148.37 },
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
- **Timestamp**: RFC 3339/ISO 8601 with `Z` (UTC). Parsed as `Instant` when needed.
- **Legacy support**: Older flat fields (e.g., `latitude`, `longitude`, `g_force`, `speed`) are supported for compatibility.

## 5. Processing Flow

1. SCDF Rabbit source reads from `telematics_work_queue.crash-detection-group`
2. SCDF routes to processor `imc-telemetry-processor`
3. Processor extracts `g_force` and emits only accidents
4. Accidents are fanned out to:
   - Rabbit sink → `vehicle-events.vehicle-events-group`
   - `imc-hdfs-sink` → HDFS append under `/insurance-megacorp/telemetry-data-v2/date=YYYY-MM-DD`


## 6. Coding Standards & Conventions

- Prefer readable, descriptive names; avoid abbreviations.
- Use early returns and guard clauses; avoid deep nesting.
- Do not catch exceptions without meaningful handling; log with context.
- Match existing formatting; do not reformat unrelated code.

## 7. Important Do's and Don'ts

- **DO** keep backward compatibility with legacy flat messages.
- **DO** treat the enhanced schema as the source of truth when present.
- **DO NOT** modify the raw JSON payload—Spark will handle flattening downstream.
- **DO NOT** commit secrets or real credentials; use the provided config templates.

## 8. Configuration

- RabbitMQ input: queue `telematics_work_queue.crash-detection-group`
- RabbitMQ accident output: queue `vehicle-events.vehicle-events-group`
- HDFS sink:
  - `hdfs.namenodeUri = hdfs://namenode:8020`
  - `hdfs.outputPath = /insurance-megacorp/telemetry-data-v2`

## 9. Versions

- Spring Boot: 3.5.3 (parent POM)
- Spring Cloud: 2024.0.0 (via BOM)
- Spark: 4.0 (Scala 2.13), Java 21
- Java (connector): 21
- Maven Wrapper: included (`./mvnw`)
- Note: No `versions.txt` currently. If introduced, align POM versions accordingly.

## 10. Deployment

- SCDF runs in Cloud Foundry; apps registered via imc-stream-manager
- Network: CF apps require egress to RabbitMQ and HDFS endpoints
- HDFS: partition by date only; write as `hdfs` user (no Kerberos)

## Notes

General documentation can live here. The plan section below is specifically parsed by `dbplan`.

<!-- devplan:start -->
## Development Plan

## Phase: Telemetry Processor
- [X] Implement function: vehicleEventsOut (tap) for g_force > threshold; emit flattened JSON
- [X] Configure bindings for input and vehicle-events output
- [X] Robust JSON handling: flatten enhanced schema; null-safe accessors for nested fields
- [X] Validation: log and drop malformed payloads
- [X] Error handling: DLQ enabled via consumer properties; base retry policy in template
- [X] Metrics: Micrometer counters for total, vehicle events, invalid
- [X] Unit tests: g_force thresholds, missing fields, malformed JSON
- [X] Integration test: end-to-end with embedded broker (testbinder)
- [X] Configurability: threshold via env; content-type header on outputs
- [X] Local smoke test: Docker RabbitMQ, declare topology, publish sample, verify queue counts (non-consuming)
- [X] Operator UX: wait-loop for message arrival and optional Rabbit UI pause

## Phase: HDFS Sink
- [X] Write Parquet with minimal schema (raw_json) and SNAPPY compression
- [X] Partition output by date in HDFS path
- [X] Hadoop client configuration: namenode URI, timeouts, buffers
- [X] File rolling policy: size/time thresholds; safe writer close on shutdown
- [X] Retry/Idempotency: handle transient HDFS errors, avoid duplicate files
- [X] Performance tuning: configurable write buffer size, batch size
- [X] Kerberos readiness: optional JAAS path (disabled by default)
- [X] Metrics: files written, bytes written, failures
- [X] Validate HDFS connection/permissions in target environment

## Phase: Stream Manager
- [X] Add functions (utilities, config/global+per-stream, auth, app registration via GitHub, streams)
- [X] Interactive menu with color/icons; global and per-stream operations
- [X] Global config.yml, per-stream config-<name>.yml, streams-index.yml
- [X] Stream CRUD UX: create, edit, delete stream configs; rename stream
- [X] Validation: verify GitHub URLs resolve to release JARs; fallback warnings
- [X] Operations: unregister default apps; register custom app by GitHub URL (menu added)
- [X] Status: show stream deployment status
- [X] Non-interactive flags: NO_PROMPT, DEBUG; exit codes for CI usage
- [X] README runbook for usage and env vars (TOKEN, SCDF_CLIENT_ID/SECRET)

## Phase: SCDF Integration
- [ ] Register apps in SCDF (processor, sink) using manager
- [ ] Create and deploy single fan-out stream; verify status transitions
- [ ] End-to-end validation with sample telemetry (vehicle_event + non-event)
- [ ] Troubleshooting: capture SCDF error responses; suggest remediation

## Phase: Documentation & Ops
- [ ] Health/readiness notes and logging guidance (levels, DLQ, retries)
- [ ] README: module runbooks and SCDF registration/stream creation guides
- [ ] Config references: templates overview and required env vars
- [ ] Gotchas: Rabbit queue/group patterns, HDFS partitions, message sizes
- [ ] Finalize PROJECT docs; add roadmap
<!-- devplan:end -->

## 12. Security & Observability

- Secrets via environment variables; no secret manager integration
- Standard logging; no additional metrics/JMX required

## 13. SCDF Stream Architecture Options

### **Stream Topology Overview**
The system requires a fan-out pattern where:
- **ALL telemetry messages** → HDFS (historical storage)
- **ONLY accident events** (g_force > 5.0) → vehicle-events queue (real-time alerts)

### **Option 1: Tap-Based Architecture (Recommended)**

**Stream Definition:**
```bash
# Main stream: All telemetry → HDFS
telematics-to-hdfs = rabbit --queues=telematics_work_queue | imc-hdfs-sink

# Tap stream: Accidents only → vehicle-events
accident-detection = :telematics-to-hdfs.rabbit > imc-telemetry-processor | rabbit --queues=vehicle_events
```

**Benefits:**
- Clean conceptual model with explicit tap relationship
- Main stream handles bulk storage, tap handles filtering
- Easy to understand and maintain in SCDF UI
- Natural order: storage first, then processing

**Configuration:**
- HDFS sink: Uses main stream consumer group
- Telemetry processor: Taps the main stream, different consumer group

### **Option 2: Parallel Consumer Groups (Current Implementation)**

**Stream Definition:**
```bash
# Parallel streams with same source
telematics-to-hdfs = rabbit --queues=telematics_work_queue | imc-hdfs-sink
accident-detection = rabbit --queues=telematics_work_queue | imc-telemetry-processor | rabbit --queues=vehicle_events
```

**Benefits:**
- Both consumers are independent and equal
- Easier to scale and monitor separately
- No dependency between the two processing paths
- Simpler SCDF stream definitions

**Configuration:**
- HDFS sink: `group=hdfs-sink-group`
- Telemetry processor: `group=crash-detection-group`

### **Option 3: Source Fanout (Alternative)**

**Stream Definition:**
```bash
# Single stream with multiple outputs
telemetry-fanout = rabbit --queues=telematics_work_queue | bridge --expression=#routing.key | log
telematics-to-hdfs = :telemetry-fanout > imc-hdfs-sink
accident-detection = :telemetry-fanout > imc-telemetry-processor | rabbit --queues=vehicle_events
```

**Benefits:**
- Explicit fanout at the source level
- Clear routing visualization in SCDF
- Can add additional processing branches easily

### **Recommendation: Option 1 (Tap-Based)**

**Rationale:**
1. **Conceptually accurate**: HDFS storage is the primary concern, accident detection is secondary processing
2. **Performance optimized**: Main stream optimized for bulk throughput to HDFS
3. **Operationally clear**: Obvious which is the main data flow vs. derived processing
4. **SCDF idiomatic**: Uses SCDF tap features as designed

**Implementation Steps:**
1. Deploy both apps to SCDF as processor and sink
2. Create main stream: `rabbit → imc-hdfs-sink`
3. Create tap stream: `:main.rabbit > imc-telemetry-processor → rabbit`
4. Monitor both streams independently

### **Current Application Configuration**

Both approaches work with current app configurations:
- HDFS sink binds to `telematics_work_queue` with `hdfs-sink-group`
- Telemetry processor binds to `telematics_work_queue` with `crash-detection-group`
- Different consumer groups ensure both receive all messages

**Environment Variables:**
```bash
# Shared source
TELEMETRY_INPUT_EXCHANGE=telematics_work_queue

# HDFS Sink
HDFS_SINK_GROUP=hdfs-sink-group

# Telemetry Processor  
TELEMETRY_INPUT_GROUP=crash-detection-group
VEHICLE_EVENTS_OUTPUT_EXCHANGE=vehicle_events
```

## 10. Future Work