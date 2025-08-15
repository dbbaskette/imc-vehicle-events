# Feature Request: Update Telemetry Data Handling for New JSON Schema

**User Story:**

As a data engineer, I want the system to correctly process, flatten, and store telemetry data that is now being sent in a new, nested JSON format, so that we can accurately capture all sensor readings and new data points.

**1. Background:**

The data format for incoming telemetry events from our generators has changed. The new format introduces a more structured, nested layout for sensor data and includes several new fields. The existing data processing pipeline was built for a flatter JSON structure and needs to be updated to be compatible with this new schema. The requirement has also been updated to ensure that **all** telemetry messages are flattened before being written to HDFS.

**New JSON Schema:**

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

**2. Proposed Architectural Changes:**

To accommodate writing flattened JSON to HDFS, the data flow must be re-architected. The `imc-telemetry-processor` will become the central component for all initial processing. It will be modified to have **two outputs**.

*   **Output 1 (HDFS Stream):** Flattens **every** incoming message and sends it to a new destination, `flattened_telemetry`.
*   **Output 2 (JDBC Stream):** Filters for high g-force events (accidents) and sends only those flattened messages to the `vehicle_events` destination.

The new stream topology will be:
1.  `:telematics_exchange > imc-telemetry-processor`
2.  `:flattened_telemetry > imc-hdfs-sink`
3.  `:vehicle_events > vehicle-events-sink: jdbc`
4.  A tap on the JDBC sink stream for logging accident events: `:vehicle_events > log`

**3. Proposed Implementation Changes:**

**`imc-telemetry-processor`**

*   **File:** `src/main/java/com/insurancemegacorp/telemetryprocessor/TelemetryProcessor.java`
    *   **Method:** Refactor the `vehicleEventsOut` function to support two outputs (e.g., by using `StreamBridge` or multiple `Function` beans).
    *   **Changes:**
        *   The function will now flatten every message.
        *   It will always route the flattened message to the first output (`-out-0`) for HDFS.
        *   It will check the `g_force` and, if it's an accident, will also route the flattened message to the second output (`-out-1`) for the JDBC sink.
*   **File:** `src/main/resources/application.yml`
    *   **Change:** Define the bindings for the two outputs, mapping them to the `flattened_telemetry` and `vehicle_events` destinations.

**`imc-stream-manager`**

*   **File:** `imc-stream-manager/stream-configs/telemetry-streams.yml`
    *   **`streams` section:** Redefine the streams to match the new architecture above.
    *   **`deployment_properties` section:** Update the HDFS sink's input binding (`spring.cloud.stream.bindings.hdfsSink-in-0.destination`) to point to `flattened_telemetry`. The partition path expression will now operate on a flat structure (e.g., `payload.driver_id`).

**`database`**

*   **File:** `database/recreate_vehicle_events.sql`
    *   **Table:** `vehicle_events`
    *   **Changes:**
        *   Rename the `event_timestamp` column to `event_time` and change its data type to `TIMESTAMP WITH TIME ZONE`.
        *   Add a new column `speed_limit_mph` (REAL).
        *   Add a new column `driver_id` (VARCHAR).
        *   Add a new column `barometric_pressure` (REAL).

*   **File:** `imc-stream-manager/stream-configs/telemetry-streams.yml`
    *   **Property:** `app.vehicle-events-sink.jdbc.consumer.columns`
    *   **Change:** Update the column mapping for the JDBC sink to match the new database schema.

**Documentation**

*   **File:** `PROJECT.md` & `README.md`
    *   **Change:** Update all schema and architecture diagrams/descriptions to reflect the new data flow and JSON format.

**4. Acceptance Criteria:**

*   The `imc-telemetry-processor` correctly flattens the nested JSON and routes it to two separate outputs.
*   The HDFS sink consumes the **flattened** JSON from the processor and correctly partitions data by date and `driver_id`.
*   The JDBC sink successfully writes the filtered, flattened data to the updated `vehicle_events` table.
*   All project documentation is updated to reflect the new architecture.
