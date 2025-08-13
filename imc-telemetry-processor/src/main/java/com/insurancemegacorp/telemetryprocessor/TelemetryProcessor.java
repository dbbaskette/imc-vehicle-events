package com.insurancemegacorp.telemetryprocessor;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.messaging.Message;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
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
    public Function<Message<byte[]>, Message<byte[]>> vehicleEventsOut() {
        // Emit ONLY vehicle events (rule: g_force > threshold) to vehicle-events queue, using FLATTENED JSON
        return in -> {
            // Count every tapped message
            meterRegistry.counter("telemetry_messages_total", "binding", "vehicleEventsOut-in-0").increment();
            try {
                JsonNode root = mapper.readTree(in.getPayload());
                double g = root.path("g_force").asDouble(0.0);
                if (g > accidentGforceThreshold) {
                    log.info("Vehicle event detected g_force={} (threshold={})", g, accidentGforceThreshold);
                    meterRegistry.counter("telemetry_vehicle_events_total").increment();
                    byte[] flattened = flattenNode(root);
                    return MessageBuilder.withPayload(flattened)
                            .copyHeaders(in.getHeaders())
                            .setHeaderIfAbsent("contentType", "application/json")
                            .build();
                }
                return null;
            } catch (Exception e) {
                log.error("Failed to parse telemetry JSON", e);
                meterRegistry.counter("telemetry_invalid_messages_total").increment();
                return null;
            }
        };
    }

    private byte[] flattenPayload(byte[] payload) throws Exception {
        JsonNode root = mapper.readTree(payload);
        return flattenNode(root);
    }

    private byte[] flattenNode(JsonNode root) throws Exception {
        ObjectNode flat = mapper.createObjectNode();

        // Top-level fields
        copyIfPresent(root, flat, "policy_id");
        copyIfPresent(root, flat, "vehicle_id");
        copyIfPresent(root, flat, "vin");
        copyIfPresent(root, flat, "timestamp");
        copyIfPresent(root, flat, "speed_mph");
        copyIfPresent(root, flat, "current_street");
        copyIfPresent(root, flat, "g_force");

        // Sensors.gps
        JsonNode sensors = root.path("sensors");
        if (sensors.isObject()) {
            JsonNode gps = sensors.path("gps");
            copyIfPresent(gps, flat, "latitude");
            copyIfPresent(gps, flat, "longitude");
            copyIfPresent(gps, flat, "altitude");
            copyIfPresent(gps, flat, "speed_ms");
            copyIfPresent(gps, flat, "bearing");
            copyIfPresent(gps, flat, "accuracy");
            copyIfPresent(gps, flat, "satellite_count");
            copyIfPresent(gps, flat, "gps_fix_time");

            // Sensors.accelerometer
            JsonNode accel = sensors.path("accelerometer");
            copyIfPresent(accel, flat, "x", "accel_x");
            copyIfPresent(accel, flat, "y", "accel_y");
            copyIfPresent(accel, flat, "z", "accel_z");

            // Sensors.gyroscope
            JsonNode gyro = sensors.path("gyroscope");
            copyIfPresent(gyro, flat, "pitch", "gyro_pitch");
            copyIfPresent(gyro, flat, "roll", "gyro_roll");
            copyIfPresent(gyro, flat, "yaw", "gyro_yaw");

            // Sensors.magnetometer
            JsonNode mag = sensors.path("magnetometer");
            copyIfPresent(mag, flat, "x", "mag_x");
            copyIfPresent(mag, flat, "y", "mag_y");
            copyIfPresent(mag, flat, "z", "mag_z");
            copyIfPresent(mag, flat, "heading");

            // Device
            JsonNode device = sensors.path("device");
            copyIfPresent(device, flat, "battery_level");
            copyIfPresent(device, flat, "signal_strength");
            copyIfPresent(device, flat, "orientation");
            copyIfPresent(device, flat, "screen_on");
            copyIfPresent(device, flat, "charging");
        }

        byte[] flattened = mapper.writeValueAsString(flat).getBytes(StandardCharsets.UTF_8);
        return flattened;
    }

    private void copyIfPresent(JsonNode src, ObjectNode dst, String fieldName) {
        if (src != null && src.has(fieldName) && !src.get(fieldName).isNull()) {
            dst.set(fieldName, src.get(fieldName));
        }
    }

    private void copyIfPresent(JsonNode src, ObjectNode dst, String fieldName, String asName) {
        if (src != null && src.has(fieldName) && !src.get(fieldName).isNull()) {
            dst.set(asName, src.get(fieldName));
        }
    }
}


