package com.insurancemegacorp.telemetryflattener;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.messaging.Message;
import org.springframework.messaging.support.MessageBuilder;

import java.nio.charset.StandardCharsets;
import java.util.function.Function;

import static org.junit.jupiter.api.Assertions.*;

class TelemetryFlattenerTest {

    private TelemetryFlattener flattener;
    private ObjectMapper mapper;
    private Function<Message<byte[]>, Message<byte[]>> flattenFunction;

    @BeforeEach
    void setUp() {
        MeterRegistry meterRegistry = new SimpleMeterRegistry();
        flattener = new TelemetryFlattener(meterRegistry);
        flattenFunction = flattener.flattenTelemetry();
        mapper = new ObjectMapper();
    }

    @Test
    void testFlattenCompleteNestedMessage() throws Exception {
        String nestedJson = """
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
            """;

        Message<byte[]> input = MessageBuilder.withPayload(nestedJson.getBytes(StandardCharsets.UTF_8)).build();
        Message<byte[]> result = flattenFunction.apply(input);

        assertNotNull(result);
        JsonNode flattened = mapper.readTree(result.getPayload());

        // Verify top-level fields
        assertEquals(200018, flattened.get("policy_id").asLong());
        assertEquals(300021, flattened.get("vehicle_id").asLong());
        assertEquals("1HGBH41JXMN109186", flattened.get("vin").asText());
        assertEquals("2024-01-15T10:30:45.123Z", flattened.get("event_time").asText());
        assertEquals(32.5, flattened.get("speed_mph").asDouble(), 0.01);
        assertEquals(35, flattened.get("speed_limit_mph").asInt());
        assertEquals("Peachtree Street", flattened.get("current_street").asText());
        assertEquals(1.18, flattened.get("g_force").asDouble(), 0.01);
        assertEquals("DRIVER-400018", flattened.get("driver_id").asText());

        // Verify GPS fields with contextual prefixes
        assertEquals(33.7701, flattened.get("gps_latitude").asDouble(), 0.0001);
        assertEquals(-84.3876, flattened.get("gps_longitude").asDouble(), 0.0001);
        assertEquals(351.59, flattened.get("gps_altitude").asDouble(), 0.01);
        assertEquals(14.5, flattened.get("gps_speed_ms").asDouble(), 0.01);
        assertEquals(148.37, flattened.get("gps_bearing").asDouble(), 0.01);
        assertEquals(2.64, flattened.get("gps_accuracy").asDouble(), 0.01);
        assertEquals(11, flattened.get("gps_satellite_count").asInt());
        assertEquals(150, flattened.get("gps_fix_time").asInt());

        // Verify sensor fields with contextual prefixes
        assertEquals(0.1234, flattened.get("accelerometer_x").asDouble(), 0.0001);
        assertEquals(-0.0567, flattened.get("accelerometer_y").asDouble(), 0.0001);
        assertEquals(0.9876, flattened.get("accelerometer_z").asDouble(), 0.0001);
        assertEquals(0.02, flattened.get("gyroscope_pitch").asDouble(), 0.01);
        assertEquals(-0.01, flattened.get("gyroscope_roll").asDouble(), 0.01);
        assertEquals(0.15, flattened.get("gyroscope_yaw").asDouble(), 0.01);
        assertEquals(25.74, flattened.get("magnetometer_x").asDouble(), 0.01);
        assertEquals(-8.73, flattened.get("magnetometer_y").asDouble(), 0.01);
        assertEquals(40.51, flattened.get("magnetometer_z").asDouble(), 0.01);
        assertEquals(148.37, flattened.get("magnetometer_heading").asDouble(), 0.01);
        assertEquals(1013.25, flattened.get("sensors_barometric_pressure").asDouble(), 0.01);

        // Verify device fields with contextual prefixes
        assertEquals(82.0, flattened.get("device_battery_level").asDouble(), 0.01);
        assertEquals(-63, flattened.get("device_signal_strength").asInt());
        assertEquals("portrait", flattened.get("device_orientation").asText());
        assertFalse(flattened.get("device_screen_on").asBoolean());
        assertTrue(flattened.get("device_charging").asBoolean());
    }

    @Test
    void testLegacyTimestampFieldMapping() throws Exception {
        String legacyJson = """
            {
              "policy_id": 200018,
              "vehicle_id": 300021,
              "timestamp": "2024-01-15T10:30:45.123Z",
              "g_force": 1.18
            }
            """;

        Message<byte[]> input = MessageBuilder.withPayload(legacyJson.getBytes(StandardCharsets.UTF_8)).build();
        Message<byte[]> result = flattenFunction.apply(input);

        assertNotNull(result);
        JsonNode flattened = mapper.readTree(result.getPayload());
        assertEquals("2024-01-15T10:30:45.123Z", flattened.get("event_time").asText());
    }

    @Test
    void testHandleMalformedJson() {
        String malformedJson = "{ invalid json }";
        Message<byte[]> input = MessageBuilder.withPayload(malformedJson.getBytes(StandardCharsets.UTF_8)).build();
        Message<byte[]> result = flattenFunction.apply(input);
        
        assertNull(result);
    }
}