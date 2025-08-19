package com.insurancemegacorp.jdbcconsumer;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.client.discovery.EnableDiscoveryClient;

/**
 * Custom JDBC Consumer Application with Prometheus metrics and Service Registry integration.
 * 
 * This application provides enhanced JDBC sink capabilities with:
 * - Prometheus metrics for monitoring
 * - Service registry integration for Cloud Foundry
 * - Custom business logic and error handling
 * - Optimized batch processing
 */
@SpringBootApplication
@EnableDiscoveryClient
public class JdbcConsumerApplication {

    public static void main(String[] args) {
        SpringApplication.run(JdbcConsumerApplication.class, args);
    }
}
