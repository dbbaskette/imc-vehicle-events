## Telemetry Processor (SCDF-Ready)

**Function:**
- `spring.cloud.function.definition=vehicleEventsOut`

**Bindings (Updated for Flat JSON):**
- `spring.cloud.stream.bindings.vehicleEventsOut-in-0.destination=telematics_exchange`
- `spring.cloud.stream.bindings.vehicleEventsOut-in-0.group=crash-detection-group`
- `spring.cloud.stream.rabbit.bindings.vehicleEventsOut-in-0.consumer.exchangeType=fanout`
- `spring.cloud.stream.bindings.vehicleEventsOut-out-0.destination=vehicle_events`

**Behavior (Simplified):**
- Consumes pre-flattened JSON (no transformation needed)
- Detects vehicle events (g_force > threshold)  
- Emits only detected events to database queue
- Zero transformation overhead with flat JSON input

**Content-Type:**
- `application/json` by default

**Operations:**
- Actuator endpoints: `/actuator/health`, `/actuator/metrics`
- Threshold configurable via `telemetry.accident.gforce.threshold` (default: 5.0)
- Metrics: `telemetry_messages_total`, `telemetry_vehicle_events_total`, `telemetry_invalid_messages_total`

**SCDF Integration:**
- Register JAR via `github_url` in stream manager
- Set function definition and binding properties
- Deploy in fanout architecture with HDFS sink

**Architecture:**
```
telematics_exchange (fanout)
    ├── imc-hdfs-sink (all flat JSON → HDFS)
    └── imc-telemetry-processor (accidents only → vehicle_events → database)
```

**Performance Benefits:**
- Pre-flattened JSON eliminates transformation overhead
- Direct field access (no nested object traversal)
- Optimized for high-throughput with minimal latency