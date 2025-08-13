package com.insurancemegacorp.vehicleevents.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.amqp.rabbit.core.RabbitAdmin;
import org.springframework.boot.SpringApplication;
import org.springframework.context.ApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

@Configuration
public class RabbitConfig {

    private static final Logger logger = LoggerFactory.getLogger(RabbitConfig.class);
    private final ApplicationContext applicationContext;
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(1);

    public RabbitConfig(ApplicationContext applicationContext) {
        this.applicationContext = applicationContext;
    }

    @Bean
    public RabbitAdmin rabbitAdmin(ConnectionFactory connectionFactory) {
        RabbitAdmin admin = new RabbitAdmin(connectionFactory);
        
        // Schedule a connection test that will shutdown the app if it fails
        scheduler.schedule(() -> {
            try {
                logger.info("Testing RabbitMQ connection...");
                admin.getQueueInfo("test-connection");
                logger.info("RabbitMQ connection successful");
            } catch (Exception e) {
                logger.error("Failed to connect to RabbitMQ after timeout. Shutting down application.", e);
                System.exit(SpringApplication.exit(applicationContext, () -> 1));
            }
        }, 15, TimeUnit.SECONDS);
        
        return admin;
    }
}