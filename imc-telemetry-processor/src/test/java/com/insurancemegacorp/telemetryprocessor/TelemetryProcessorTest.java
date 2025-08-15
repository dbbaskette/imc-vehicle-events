package com.insurancemegacorp.telemetryprocessor;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.cloud.stream.function.StreamBridge;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.messaging.Message;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.RabbitMQContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;

import static org.assertj.core.api.Assertions.assertThat;

@Testcontainers
@SpringBootTest(properties = {
        "spring.cloud.function.definition=vehicleEventsOut,testSink",
        "telemetry.accident.gforce.threshold=5.0",
        "spring.cloud.stream.bindings.vehicleEventsOut-in-0.destination=telematics_exchange",
        "spring.cloud.stream.bindings.vehicleEventsOut-out-0.destination=vehicle_events",
        "spring.cloud.stream.bindings.testSink-in-0.destination=vehicle_events",
        "spring.cloud.stream.rabbit.bindings.vehicleEventsOut-in-0.consumer.exchangeType=fanout",
        "spring.cloud.stream.rabbit.bindings.vehicleEventsOut-out-0.producer.exchangeType=fanout",
        "spring.cloud.stream.rabbit.bindings.testSink-in-0.consumer.exchangeType=fanout",
        "spring.cloud.stream.rabbit.default.producer.exchangeType=fanout"
})
class TelemetryProcessorTest {

    static BlockingQueue<Message<?>> queue = new LinkedBlockingQueue<>();

    @Bean
    public Consumer<Message<?>> testSink() {
        return message -> {
            System.out.println("Received message: " + message);
            queue.add(message);
        };
    }

    @Container
    static RabbitMQContainer rabbit = new RabbitMQContainer("rabbitmq:3.8-management");

    @DynamicPropertySource
    static void rabbitmqProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.rabbitmq.host", rabbit::getHost);
        registry.add("spring.rabbitmq.port", rabbit::getAmqpPort);
    }

    @Autowired
    private StreamBridge streamBridge;

    @Test
    void emitsVehicleEventWhenGForceAboveThreshold() throws Exception {
        // Send complete flat JSON matching new schema
        String flattenedJson = """
            {
              "policy_id": 200018,
              "vehicle_id": 300021,
              "vin": "1HGBH41JXMN109186",
              "event_time": "2024-01-15T10:30:45.123Z",
              "speed_mph": 32.5,
              "speed_limit_mph": 35,
              "current_street": "Peachtree Street",
              "g_force": 6.2,
              "driver_id": 400018,
              "gps_latitude": 33.7701,
              "gps_longitude": -84.3876,
              "gps_altitude": 351.59,
              "gps_speed": 14.5,
              "gps_bearing": 148.37,
              "gps_accuracy": 2.64,
              "gps_satellite_count": 11,
              "gps_fix_time": 150,
              "accelerometer_x": 0.1234,
              "accelerometer_y": -0.0567,
              "accelerometer_z": 0.9876,
              "gyroscope_x": 0.02,
              "gyroscope_y": -0.01,
              "gyroscope_z": 0.15,
              "magnetometer_x": 25.74,
              "magnetometer_y": -8.73,
              "magnetometer_z": 40.51,
              "magnetometer_heading": 148.37,
              "barometric_pressure": 1013.25,
              "device_battery_level": 82,
              "device_signal_strength": -63,
              "device_orientation": "portrait",
              "device_screen_on": false,
              "device_charging": true
            }""";
        
        // Wait a moment for consumer to be ready
        Thread.sleep(500);
        streamBridge.send("telematics_exchange", flattenedJson.getBytes());

        Message<?> out = queue.poll(5, TimeUnit.SECONDS);
        assertThat(out).isNotNull();
        String outStr = new String((byte[]) out.getPayload());
        assertThat(outStr).contains("\"g_force\":6.2");
        assertThat(outStr).contains("\"driver_id\":400018");
        assertThat(outStr).contains("\"event_time\":\"2024-01-15T10:30:45.123Z\"");
        assertThat(outStr).contains("\"gps_latitude\":33.7701");
        assertThat(outStr).contains("\"device_battery_level\":82");
    }

    @Test
    void dropsWhenBelowThreshold() throws Exception {
        String json = "{\"g_force\": 1.2}";
        streamBridge.send("telematics_exchange", json.getBytes());

        Message<?> out = queue.poll(200, TimeUnit.MILLISECONDS);
        assertThat(out).isNull();
    }
}


