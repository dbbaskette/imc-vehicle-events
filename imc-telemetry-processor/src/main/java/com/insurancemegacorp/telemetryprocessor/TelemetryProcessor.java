package com.insurancemegacorp.telemetryprocessor;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;

import java.util.function.Function;

@Component
public class TelemetryProcessor {
    private static final Logger log = LoggerFactory.getLogger(TelemetryProcessor.class);
    private final ObjectMapper mapper = new ObjectMapper();
    private final MeterRegistry meterRegistry;

    @Value("${telemetry.accident.gforce.threshold:5.0}")
    private double accidentGforceThreshold;

    public TelemetryProcessor(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
    }

    @Bean
    public Function<String, String> vehicleEventsOut() {
        // Emit ONLY vehicle events (rule: g_force > threshold) from already-flattened JSON
        return jsonMessage -> {
            // Count every processed message
            meterRegistry.counter("telemetry_messages_total", "binding", "vehicleEventsOut-in-0").increment();
            try {
                JsonNode root = mapper.readTree(jsonMessage);
                double g = root.path("g_force").asDouble(0.0);
                if (g > accidentGforceThreshold) {
                    log.info("Vehicle event detected g_force={} (threshold={})", g, accidentGforceThreshold);
                    meterRegistry.counter("telemetry_vehicle_events_total").increment();
                    // Message is already flattened, just pass it through
                    return jsonMessage;
                }
                return null;
            } catch (Exception e) {
                log.error("Failed to parse telemetry JSON", e);
                meterRegistry.counter("telemetry_invalid_messages_total").increment();
                return null;
            }
        };
    }

}


