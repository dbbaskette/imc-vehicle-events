# Project Brief: IMC Rabbit + Spark Suite

## 1. Project Overview & Goal

- **Primary goal**: Ingest telematics events from RabbitMQ and process them in Spark.
  - Spark will:
    - Read raw JSON from RabbitMQ queue `telematics_raw_for_spark` (forwarded by connector)
    - Flatten the JSON structure
    - Detect accidents (primary rule: `g_force > 5.0`)
      - If accident: write to Greenplum accident table (via Greenplum Spark Connector)
      - Also publish the flattened accident record to Rabbit: exchange/queue `vehicle-events` (consumers use group `vehicle-events-group`)
    - Write all flattened records to HDFS as Parquet (every record)
  - Demo scale: tens of events/sec; keep simple and low-latency.
  - Modules:
    - `imc-rabbit-spark-connector`: Spring Cloud Stream Rabbit connector that consumes raw telemetry JSON; provides optional output binding to publish accidents produced by Spark.
    - `imc-spark-processor`: Spark processor for flattening, detection, HDFS output, Greenplum writes, and accident publish to Rabbit.



- **End users**: Internal analytics/claims platforms and real-time monitoring tools.

## 2. Tech Stack

- **Language**: Java 21
- **Frameworks**: Spring Boot 3.5.3, Spring Cloud Stream 2024.0.0 (Rabbit binder), Spark 4.0 (Scala 2.13)
- **Database**: Greenplum
- **Messaging**: RabbitMQ
- **Logging**: SLF4J
- **Build**: Maven with Maven Wrapper (`./mvnw`)

## 3. Architecture & Design

- **High-Level Architecture**:
  - Connector: Spring Cloud Stream `Consumer<byte[]>` to optionally receive from Rabbit (logs receipt; no transform). May be disabled where Spark reads directly.
  - Spark: Structured Streaming job that reads from RabbitMQ, flattens, detects accidents, writes outputs.
- **Processing**:
  - Connector: minimal responsibility; raw JSON only; optional producer to publish accidents.
  - Spark: source of truth for processing pipeline.
- **Backward compatibility**: Enhanced schema preferred; legacy flat fields supported during flattening.
- **Directory Structure**:
  - `imc-rabbit-spark-connector/`: Spring Boot connector and its `application*.yml.template` files
  - `imc-spark-processor/`: Spark job and its config templates

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

1. Connector consumes raw JSON from RabbitMQ queue `telematics_work_queue` and always forwards it unchanged to queue `telematics_raw_for_spark`.
2. Spark reads raw JSON from RabbitMQ queue `telematics_raw_for_spark`.
3. Flatten JSON into a canonical schema (support enhanced and legacy fields).
4. Accident detection:
   - Primary rule: `g_force > 5.0` → accident
   - If accident: write to Greenplum accident table and publish to Rabbit `vehicle-events` (group `vehicle-events-group`).
5. Write all flattened records to HDFS as Parquet at `/insurance-megacorp/telemetry-data-v2/date=__HIVE_DEFAULT_PARTITION__` (partition by date only).


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

- RabbitMQ input (Connector): queue `telematics_work_queue`
- RabbitMQ input (Spark): queue `telematics_raw_for_spark`
- RabbitMQ accident output: exchange/queue `vehicle-events` (consumers use group `vehicle-events-group`)
- Content-Type: `application/json`
- Connector templates: `imc-rabbit-spark-connector/src/main/resources/application*.yml.template`
- Spark processor config (untracked): `imc-spark-processor/src/main/resources/spark-processor.conf.template` → copy to `spark-processor.conf`
  - Keys:
    - `spark.master = <spark://host:port | yarn | k8s master>`
    - `rabbit.uri = amqp://user:pass@host:5672/vhost`
    - `rabbit.inputQueue = telematics_work_queue`
    - `rabbit.accidentExchange = vehicle-events`
    - `hdfs.namenodeUri = hdfs://namenode:8020`
    - `hdfs.outputPath = /insurance-megacorp/telemetry-data-v2`
    - `greenplum.url = jdbc:pivotal:greenplum://host:port;DatabaseName=db`
    - `greenplum.user = <user>`
    - `greenplum.password = <password>`
    - `greenplum.table = schema.accidents`
    - `processing.triggerMs = 2000`

## 9. Versions

- Spring Boot: 3.5.3 (parent POM)
- Spring Cloud: 2024.0.0 (via BOM)
- Spark: 4.0 (Scala 2.13), Java 21
- Java (connector): 21
- Maven Wrapper: included (`./mvnw`)
- Note: No `versions.txt` currently. If introduced, align POM versions accordingly.

## 10. Performance & Deployment

- Throughput: tens of events/sec (demo)
- Trigger: recommend micro-batch trigger of 2s; no watermarking
- HDFS: small test cluster; partition by date only; write as `hdfs` user (no Kerberos)
- Deployment: Spark runs on separate server/cluster; pass master and endpoints via `spark-processor.conf`; package uber-jar with Spark deps provided

## 11. Development Plan Checklist

Phase A: Baseline and versions
- [x] Update Spark module to Spark 4.0 (Scala 2.13), Java 21 in POM
- [x] Add shaded/assembly packaging for Spark job (provided Spark deps)
- [x] Verify root build of both modules

Phase B: Config templates
- [x] Add `spark-processor.conf.template` with Rabbit, HDFS, Greenplum, trigger settings
- [x] Document local `spark-processor.conf` (untracked) and env var overrides
- [x] Add connector consumer `auto-startup` toggle in templates

Phase C: Spark ingestion
- [x] Implement Rabbit ingestion in Spark (RabbitMQ Java client-based receiver)
- [x] Make Rabbit credentials and queue configurable
- [ ] Integration test with local Rabbit (docker-compose)

Phase D: Flattening and schema
- [x] Implement JSON flattening for enhanced schema; support legacy fields
- [ ] Define canonical columns/types; add unit tests

Phase E: Accident detection and outputs
- [x] Implement `g_force > 5.0` rule
- [x] Write accidents to Greenplum via PostgreSQL JDBC (compatible with Greenplum)
- [x] Publish accidents to Rabbit `vehicle-events`

Phase F: HDFS Parquet sink
- [x] Write all flattened records to Parquet at `/insurance-megacorp/telemetry-data-v2/date=__HIVE_DEFAULT_PARTITION__`
- [x] Configure checkpointing, rollover, and partitioning by date only

Phase G: Observability and ops
- [x] Standard logging for both modules
- [ ] Basic health/readiness notes for connector

Phase H: Packaging and deployment
- [ ] Build Spark uber-jar; document spark-submit with `--properties-file`/conf
- [ ] Update README with runbooks

Phase I: Demo validation
- [ ] Run `imc-telematics-gen` to generate events
- [ ] End-to-end verification: Rabbit → Spark → HDFS + GP + Rabbit accidents
- [ ] Document gotchas

## 12. Security & Observability

- Secrets via environment variables; no secret manager integration
- Standard logging; no additional metrics/JMX required

## 10. Future Work
