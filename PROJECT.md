# Project Brief: IMC Vehicle Events

## 1. Project Overview & Goal

- **Primary goal**: Consume telematics events from RabbitMQ using Spring Cloud Stream, detect potential crash events in real time, and make the raw JSON available downstream. Schema flattening will occur later in a Spark processor (to be implemented).
- **End users**: Internal analytics/claims platforms and real-time monitoring tools.

## 2. Tech Stack

- **Language**: Java 21
- **Frameworks**: Spring Boot 3.5.3, Spring Cloud Stream 2024.0.0 (Rabbit binder)
- **Messaging**: RabbitMQ
- **Logging**: SLF4J
- **Build**: Maven with Maven Wrapper (`./mvnw`)

## 3. Architecture & Design

- **High-Level Architecture**: Event-driven microservice. Spring Cloud Stream `Consumer<byte[]>` bound to RabbitMQ queue `telematics_work_queue` with consumer group `crash-detection-group`.
- **Processing**:
  - Receive raw JSON payloads from RabbitMQ.
  - Do not transform/process payloads in the connector.
  - Preserve and forward raw JSON for Spark processing where the schema will be flattened.
- **Backward compatibility**: Accepts both the legacy flat schema and the enhanced schema; detection is tolerant of missing fields.
- **Directory Structure**:
  - `src/main/java/com/insurancemegacorp/vehicleevents/`: Spring Boot app
  - `src/main/resources/`: Configuration templates (`application*.yml.template`)

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

1. RabbitMQ message received as bytes; raw JSON string is logged.
2. If the payload contains `sensors`, treat it as enhanced schema; otherwise, treat as legacy flat schema.
3. Crash detection:
   - Primary rule: `g_force > 5.0` indicates crash.
   - Fallbacks: Optional magnitude checks from accelerometer can be added later if desired.
4. Raw JSON is preserved for downstream Spark processor which will handle flattening and further analytics.

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

- Queue: `telematics_work_queue`
- Group: `crash-detection-group`
- Content-Type: `application/json`
- Templates: `application.yml.template`, `application-cloud.yml.template`, `application-tunnel.yml.template`

## 9. Versions

- Spring Boot: 3.5.3 (parent POM)
- Spring Cloud: 2024.0.0 (via BOM)
- Java: 21
- Maven Wrapper: included (`./mvnw`)
- Note: No `versions.txt` currently. If introduced, align POM versions accordingly.

## 10. Future Work

- Implement Spark processor to ingest the raw JSON, flatten schema, and write to downstream storage/analytics systems.
- Optionally publish the raw JSON to a topic/queue dedicated for Spark ingestion.
- Consider additional crash heuristics (accelerometer/gyroscope patterns) if needed.

## 11. Open Questions

- Should we add an output binding to forward raw JSON to a Spark-ingestion queue now, or wait for Spark implementation?
- Confirm final crash threshold and any multi-sensor criteria.