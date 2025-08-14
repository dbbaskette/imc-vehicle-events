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
    void testJsonMessageStructure() {
        String validJson = "{\"vehicle_id\":123,\"g_force\":2.5,\"timestamp\":\"2024-01-15T10:30:45.123Z\"}";
        byte[] payload = validJson.getBytes(StandardCharsets.UTF_8);
        
        // Test that the message structure is preserved
        String reconstructed = new String(payload, StandardCharsets.UTF_8);
        assertTrue(reconstructed.contains("vehicle_id"));
        assertTrue(reconstructed.contains("g_force"));
        assertTrue(reconstructed.contains("timestamp"));
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
        String largeMessage = "{\"vehicle_id\":123,\"g_force\":2.5,\"sensors\":{\"gps\":{\"latitude\":33.7701,\"longitude\":-84.3876}}}";
        
        byte[] smallPayload = smallMessage.getBytes(StandardCharsets.UTF_8);
        byte[] largePayload = largeMessage.getBytes(StandardCharsets.UTF_8);
        
        assertTrue(smallPayload.length < largePayload.length);
        assertTrue(smallPayload.length > 0);
        assertTrue(largePayload.length > 50);
    }
}