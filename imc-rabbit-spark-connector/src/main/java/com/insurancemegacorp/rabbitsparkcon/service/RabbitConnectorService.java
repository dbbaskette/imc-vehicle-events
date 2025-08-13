package com.insurancemegacorp.rabbitsparkcon.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.cloud.stream.function.StreamBridge;
import org.springframework.context.annotation.Bean;
import org.springframework.messaging.Message;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.stereotype.Service;

import java.util.function.Consumer;

@Service
public class RabbitConnectorService {

    private static final Logger logger = LoggerFactory.getLogger(RabbitConnectorService.class);

    private final StreamBridge streamBridge;

    public RabbitConnectorService(StreamBridge streamBridge) {
        this.streamBridge = streamBridge;
    }

    @Bean
    public Consumer<byte[]> consumeRawTelematics() {
        return rawBytes -> {
            String payload = new String(rawBytes);
            logger.info("Received raw telemetry JSON ({} bytes)", rawBytes.length);
            logger.debug("Payload: {}", payload);

            // Forward payload unchanged to Spark ingest destination via producer binding
            Message<byte[]> msg = MessageBuilder.withPayload(rawBytes)
                    .setHeader("contentType", "application/json")
                    .build();
            boolean sent = streamBridge.send("rawToSpark-out-0", msg);
            if (!sent) {
                logger.warn("Failed to forward message to rawToSpark-out-0");
            }
        };
    }
}


