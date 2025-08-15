package com.insurancemegacorp.telemetryflattener;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.context.annotation.Bean;
import org.springframework.messaging.Message;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.util.function.Function;

@Component
public class TelemetryFlattener {
    private static final Logger log = LoggerFactory.getLogger(TelemetryFlattener.class);
    private final ObjectMapper mapper = new ObjectMapper();
    private final MeterRegistry meterRegistry;

    public TelemetryFlattener(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
    }

    @Bean
    public Function<Message<byte[]>, Message<byte[]>> flattenTelemetry() {
        return in -> {
            meterRegistry.counter("telemetry_messages_total", "binding", "flattenTelemetry-in-0").increment();
            try {
                JsonNode root = mapper.readTree(in.getPayload());
                byte[] flattened = flattenNode(root);
                meterRegistry.counter("telemetry_flattened_total").increment();
                
                return MessageBuilder.withPayload(flattened)
                        .copyHeaders(in.getHeaders())
                        .setHeaderIfAbsent("contentType", "application/json")
                        .build();
            } catch (Exception e) {
                log.error("Failed to flatten telemetry JSON", e);
                meterRegistry.counter("telemetry_flatten_errors_total").increment();
                return null;
            }
        };
    }

    private byte[] flattenNode(JsonNode root) throws Exception {
        ObjectNode flat = mapper.createObjectNode();

        // Top-level fields from new schema
        copyIfPresent(root, flat, "policy_id");
        copyIfPresent(root, flat, "vehicle_id");
        copyIfPresent(root, flat, "vin");
        copyIfPresent(root, flat, "event_time");
        copyIfPresent(root, flat, "speed_mph");
        copyIfPresent(root, flat, "speed_limit_mph");
        copyIfPresent(root, flat, "current_street");
        copyIfPresent(root, flat, "g_force");
        copyIfPresent(root, flat, "driver_id");

        // Support legacy timestamp field name as well
        if (!root.has("event_time") && root.has("timestamp")) {
            copyIfPresent(root, flat, "timestamp", "event_time");
        }

        // Sensors object
        JsonNode sensors = root.path("sensors");
        if (sensors.isObject()) {
            // GPS data with contextual prefixes
            JsonNode gps = sensors.path("gps");
            copyIfPresent(gps, flat, "latitude", "gps_latitude");
            copyIfPresent(gps, flat, "longitude", "gps_longitude");
            copyIfPresent(gps, flat, "altitude", "gps_altitude");
            copyIfPresent(gps, flat, "speed_ms", "gps_speed_ms");
            copyIfPresent(gps, flat, "bearing", "gps_bearing");
            copyIfPresent(gps, flat, "accuracy", "gps_accuracy");
            copyIfPresent(gps, flat, "satellite_count", "gps_satellite_count");
            copyIfPresent(gps, flat, "gps_fix_time", "gps_fix_time");

            // Accelerometer data with contextual prefixes
            JsonNode accel = sensors.path("accelerometer");
            copyIfPresent(accel, flat, "x", "accelerometer_x");
            copyIfPresent(accel, flat, "y", "accelerometer_y");
            copyIfPresent(accel, flat, "z", "accelerometer_z");

            // Gyroscope data with contextual prefixes
            JsonNode gyro = sensors.path("gyroscope");
            copyIfPresent(gyro, flat, "pitch", "gyroscope_pitch");
            copyIfPresent(gyro, flat, "roll", "gyroscope_roll");
            copyIfPresent(gyro, flat, "yaw", "gyroscope_yaw");

            // Magnetometer data with contextual prefixes
            JsonNode mag = sensors.path("magnetometer");
            copyIfPresent(mag, flat, "x", "magnetometer_x");
            copyIfPresent(mag, flat, "y", "magnetometer_y");
            copyIfPresent(mag, flat, "z", "magnetometer_z");
            copyIfPresent(mag, flat, "heading", "magnetometer_heading");

            // Barometric pressure (direct field in sensors)
            copyIfPresent(sensors, flat, "barometric_pressure", "sensors_barometric_pressure");

            // Device data with contextual prefixes
            JsonNode device = sensors.path("device");
            copyIfPresent(device, flat, "battery_level", "device_battery_level");
            copyIfPresent(device, flat, "signal_strength", "device_signal_strength");
            copyIfPresent(device, flat, "orientation", "device_orientation");
            copyIfPresent(device, flat, "screen_on", "device_screen_on");
            copyIfPresent(device, flat, "charging", "device_charging");
        }

        return mapper.writeValueAsString(flat).getBytes(StandardCharsets.UTF_8);
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