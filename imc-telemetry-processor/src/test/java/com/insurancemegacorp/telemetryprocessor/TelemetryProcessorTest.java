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
        "spring.cloud.function.definition=vehicleEventsOut;testSink",
        "telemetry.accident.gforce.threshold=5.0",
        "spring.cloud.stream.bindings.vehicleEventsOut-in-0.destination=flattened_telemetry_exchange",
        "spring.cloud.stream.bindings.vehicleEventsOut-out-0.destination=vehicle_events",
        "spring.cloud.stream.bindings.testSink-in-0.destination=vehicle_events"
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
        // Send flattened JSON as the processor now expects pre-flattened input with contextual field names
        String flattenedJson = "{\"g_force\": 6.2, \"policy_id\":1, \"vehicle_id\":2, \"gps_latitude\":1.0, \"gps_longitude\":2.0}";
        streamBridge.send("vehicleEventsOut-in-0", flattenedJson.getBytes());

        Message<?> out = queue.poll(2, TimeUnit.SECONDS);
        assertThat(out).isNotNull();
        String outStr = new String((byte[]) out.getPayload());
        assertThat(outStr).contains("\"g_force\":6.2");
        assertThat(outStr).contains("\"gps_latitude\":1.0");
        assertThat(outStr).contains("\"gps_longitude\":2.0");
    }

    @Test
    void dropsWhenBelowThreshold() throws Exception {
        String json = "{\"g_force\": 1.2}";
        streamBridge.send("vehicleEventsOut-in-0", json.getBytes());

        Message<?> out = queue.poll(200, TimeUnit.MILLISECONDS);
        assertThat(out).isNull();
    }
}


