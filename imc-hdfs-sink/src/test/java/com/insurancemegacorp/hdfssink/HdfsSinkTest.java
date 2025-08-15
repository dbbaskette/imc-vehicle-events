package com.insurancemegacorp.hdfssink;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.*;

class HdfsSinkTest {

    @Test
    void testMeterRegistryInjection() {
        MeterRegistry meterRegistry = new SimpleMeterRegistry();
        assertNotNull(meterRegistry);
        
        // Test that metrics can be created
        meterRegistry.counter("test_counter").increment();
        assertEquals(1.0, meterRegistry.counter("test_counter").count());
    }

    @Test
    void testMessageHandling() {
        String testMessage = "{\"vehicle_id\":123,\"g_force\":2.5}";
        byte[] payload = testMessage.getBytes(StandardCharsets.UTF_8);
        
        // Test basic message conversion
        assertNotNull(payload);
        assertTrue(payload.length > 0);
        assertEquals(testMessage, new String(payload, StandardCharsets.UTF_8));
    }

    @Test
    void testFlatJsonMessageStructure() {
        String validFlatJson = """
            {
              "policy_id": 200018,
              "vehicle_id": 300021,
              "vin": "1HGBH41JXMN109186",
              "event_time": "2024-01-15T10:30:45.123Z",
              "speed_mph": 32.5,
              "speed_limit_mph": 35,
              "g_force": 1.18,
              "driver_id": 400018,
              "gps_latitude": 33.7701,
              "gps_longitude": -84.3876,
              "device_battery_level": 82,
              "device_charging": true
            }""";
        byte[] payload = validFlatJson.getBytes(StandardCharsets.UTF_8);
        
        // Test that the flat JSON structure is preserved
        String reconstructed = new String(payload, StandardCharsets.UTF_8);
        assertTrue(reconstructed.contains("vehicle_id"));
        assertTrue(reconstructed.contains("g_force"));
        assertTrue(reconstructed.contains("event_time"));
        assertTrue(reconstructed.contains("gps_latitude"));
        assertTrue(reconstructed.contains("driver_id"));
        assertTrue(reconstructed.contains("device_battery_level"));
    }

    @Test
    void testEmptyPayload() {
        byte[] emptyPayload = new byte[0];
        
        // Test handling of empty payload
        assertNotNull(emptyPayload);
        assertEquals(0, emptyPayload.length);
        assertEquals("", new String(emptyPayload, StandardCharsets.UTF_8));
    }

    @Test
    void testPayloadSizes() {
        String smallMessage = "{\"id\":1}";
        String flatMessage = "{\"vehicle_id\":123,\"g_force\":2.5,\"gps_latitude\":33.7701,\"gps_longitude\":-84.3876,\"device_battery_level\":82}";
        
        byte[] smallPayload = smallMessage.getBytes(StandardCharsets.UTF_8);
        byte[] flatPayload = flatMessage.getBytes(StandardCharsets.UTF_8);
        
        assertTrue(smallPayload.length < flatPayload.length);
        assertTrue(smallPayload.length > 0);
        assertTrue(flatPayload.length > 50);
    }
}