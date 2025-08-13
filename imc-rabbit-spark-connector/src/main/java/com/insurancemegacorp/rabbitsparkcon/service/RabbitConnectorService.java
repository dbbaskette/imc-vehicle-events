package com.insurancemegacorp.rabbitsparkcon.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Service;

import java.util.function.Consumer;

@Service
public class RabbitConnectorService {

    private static final Logger logger = LoggerFactory.getLogger(RabbitConnectorService.class);

    @Bean
    public Consumer<byte[]> consumeRawTelematics() {
        return rawBytes -> {
            String payload = new String(rawBytes);
            // Minimal responsibility: log receipt and leave processing to Spark downstream
            logger.info("Received raw telemetry JSON ({} bytes)", rawBytes.length);
            logger.debug("Payload: {}", payload);
            // Forwarding to Spark is expected to be handled outside this app (e.g., Spark Structured Streaming reads from the same queue or an intermediate topic)
        };
    }
}


