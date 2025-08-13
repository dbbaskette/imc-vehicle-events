package com.insurancemegacorp.telemetryprocessor;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.messaging.Message;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.stereotype.Component;

import java.util.function.Function;

@Component
public class TelemetryProcessor {
    private static final Logger log = LoggerFactory.getLogger(TelemetryProcessor.class);
    private final ObjectMapper mapper = new ObjectMapper();

    @Bean
    public Function<Message<byte[]>, Message<byte[]>> processTelemetry() {
        // Forward ALL events to HDFS sink (via processTelemetry-out-0)
        return in -> MessageBuilder.withPayload(in.getPayload()).copyHeaders(in.getHeaders()).build();
    }

    @Bean
    public Function<Message<byte[]>, Message<byte[]>> accidentsOut() {
        // Emit ONLY accidents to vehicle-events
        return in -> {
            byte[] payload = in.getPayload();
            try {
                JsonNode node = mapper.readTree(payload);
                double g = node.path("g_force").asDouble(0.0);
                if (g > 5.0) {
                    log.info("Accident detected g_force={}", g);
                    return MessageBuilder.withPayload(payload).copyHeaders(in.getHeaders()).build();
                }
                return null;
            } catch (Exception e) {
                log.error("Failed to parse telemetry JSON", e);
                return null;
            }
        };
    }
}


