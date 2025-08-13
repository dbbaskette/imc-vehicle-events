Yes. The telemetry processor is SCDF-ready.
Function
spring.cloud.function.definition=vehicleEventsOut
Bindings
spring.cloud.stream.bindings.vehicleEventsOut-in-0.destination=telematics_work_queue
spring.cloud.stream.bindings.vehicleEventsOut-in-0.group=crash-detection-group
spring.cloud.stream.rabbit.bindings.vehicleEventsOut-in-0.consumer.exchangeType=direct
spring.cloud.stream.bindings.vehicleEventsOut-out-0.destination=vehicle-events
content-type is application/json by default
Behavior
Consumes raw JSON, detects vehicle events (g_force > threshold), emits only detected events
Output exchange should be topic (default for producer); let binder create it or ensure existing is topic
Ops
Exposes Actuator: /actuator/health, /actuator/metrics
Threshold configurable via env/property
To plug into SCDF, register the JAR (via github_url), set function definition and the above binding properties on the processor step.