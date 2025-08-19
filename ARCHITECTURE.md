# IMC Telemetry Stream - Architecture Deep Dive

This document provides a detailed look into the architectural decisions, component designs, and technical rationale for the IMC Telemetry Stream project. It complements the main `README.md` by explaining the "why" behind the "what."

## 1. Core Architectural Principles

The system was designed around a few key principles to meet the demands of a high-volume, real-time data pipeline:

-   **🚀 Zero Transformation Overhead**: Eliminate in-stream data transformation to maximize throughput and reduce latency.
-   **🛡️ Enhanced Reliability & Data Integrity**: Ensure data is processed correctly and reliably, even in a distributed, multi-instance environment.
-   **📊 Production-Grade Observability**: Provide deep insights into application performance, data quality, and system health through comprehensive metrics.
-   **🔧 Simplified Maintainability**: Keep the architecture as simple as possible with fewer moving parts.

---

## 2. Key Design Decisions & Rationale

### Decision: Adopt a Pre-Flattened JSON Schema

**Background**: The system initially received a nested JSON payload which required a dedicated processing step (`telemetry-flattener`) to prepare the data for storage in HDFS and the database.

**Problem**: The in-stream flattening process introduced several challenges:
-   **Performance Bottleneck**: JSON parsing and object transformation consumed significant CPU cycles, limiting overall throughput.
-   **Increased Complexity**: It required an extra application in the stream, making the topology more complex to manage and deploy.
-   **Maintenance Overhead**: Any schema change required updates to the flattener logic.

**Solution**: The architecture was simplified by mandating that the upstream telemetry generator sends data in a **pre-flattened JSON format**.

**Benefits**:
-   **Maximum Performance**: The `imc-telemetry-processor` and `imc-hdfs-sink` can now consume messages directly with no transformation, dramatically increasing throughput.
-   **Simplified Architecture**: The `telemetry-flattener` component was completely removed, resulting in a simpler, more efficient fanout architecture.
-   **Database Ready**: The flat JSON fields map directly to database columns, simplifying the JDBC sink configuration.

---

### Decision: Engineer a Robust, Multi-Instance HDFS Sink

**Background**: The initial HDFS sink implementation had critical flaws that would have caused data corruption and incorrect analytics in a production, multi-instance environment.

**Problem 1: Incorrect Partitioning Logic**
-   The sink was assigning an entire batch of messages to the HDFS partition derived from the *first* message in that batch. This meant data for `driver_id=400017` could be written to the partition for `driver_id=400016`, corrupting the data lake.

**Problem 2: File Name Collisions**
-   Multiple instances of the sink running in parallel (a standard cloud deployment pattern) would attempt to write to files with identical names, leading to HDFS file corruption.

**Solution**: The `imc-hdfs-sink` was re-engineered with a more sophisticated, instance-aware design.

**Key Features of the Optimized HDFS Sink**:
-   **Message-Level Partitioning**: The sink now groups messages by their correct partition key (`date` and `driver_id`) *before* writing, ensuring every message lands in the correct HDFS directory.
-   **Instance-Aware File Naming**: A unique instance ID (derived from `CF_INSTANCE_INDEX` or hostname) and a UUID are incorporated into filenames. This completely eliminates the risk of file collisions between instances.
    -   *Example Filename*: `normal-20250815_143052-cf-0-a1b2c3d4.parquet`
-   **Multi-Writer Support**: Instead of a single file writer, the sink maintains a map of concurrent writers, one for each active partition. This allows for parallel writes to different partitions (e.g., for different drivers) simultaneously.
-   **Defensive Design**:
    -   An in-memory queue buffers incoming messages, preventing data loss during transient HDFS outages.
    -   Failed batches are safely requeued for retry with exponential backoff.
    -   A graceful shutdown hook (`@PreDestroy`) ensures all buffered data is flushed and writers are closed safely.
-   **Comprehensive Metrics**: The sink exposes detailed Micrometer metrics for monitoring throughput, errors, file creation, and bytes written.

---

### Decision: Build a Custom JDBC Consumer for Production Monitoring

**Background**: The standard Spring Cloud Stream JDBC Sink provides basic functionality but lacks the advanced monitoring, reliability, and cloud-native features required for a mission-critical production environment.

**Problem**: Using the standard sink would leave operators with significant visibility gaps. It would be difficult to monitor data quality, diagnose performance issues, or integrate cleanly into a cloud environment with service discovery.

**Solution**: A new `imc-jdbc-consumer` application was created to serve as a production-grade replacement for the standard JDBC sink.

**Comparison of Features**:

| Feature                 | Standard JDBC Sink        | Custom `imc-jdbc-consumer`          |
| ----------------------- | ------------------------- | ----------------------------------- |
| **Metrics**             | Basic health only         | **5 comprehensive Prometheus metrics**  |
| **Service Discovery**   | None                      | **Eureka integration for Cloud Foundry**|
| **Error Handling**      | Basic retry               | **Advanced retry with classification**  |
| **Monitoring**          | Limited actuator endpoints| **Rich actuator endpoints (DB health)** |
| **Batch Processing**    | Fixed batching            | **Configurable batch size & timeout**   |
| **Data Quality**        | No tracking               | **Null parameter tracking metric**      |
| **Performance Insights**| None                      | **Processing duration histograms**      |

**Key Features of the Custom JDBC Consumer**:

1.  **5 Core Prometheus Metrics**:
    -   `jdbc_consumer_messages_total`: Total messages processed, tagged by table.
    -   `jdbc_consumer_messages_success`: Count of successful database writes.
    -   `jdbc_consumer_messages_error`: Count of failed writes, tagged by error type.
    -   `jdbc_consumer_message_duration`: A histogram measuring message processing latency.
    -   `jdbc_consumer_null_parameters_total`: A data quality metric tracking columns with null values.

2.  **Service Registry Integration**: As a Eureka client, it registers itself with a service registry, enabling dynamic discovery in cloud environments like Cloud Foundry.

3.  **Enhanced Error Handling**: Includes configurable retry logic with exponential backoff to gracefully handle transient database issues.

4.  **Rich Monitoring Endpoints**: Exposes key actuator endpoints for deep operational insight:
    -   `/actuator/health`: Overall application health.
    -   `/actuator/health/db`: Specific status of the database connection pool.
    -   `/actuator/prometheus`: All metrics exported in Prometheus format for easy scraping.

This custom component provides the observability and reliability needed to confidently run the database ingestion part of the pipeline in production.

---

## 3. Stream & Data Flow

The combination of these design decisions results in the current simplified fanout architecture:

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

This design is highly performant, scalable, and provides the necessary operational insight for production use.

