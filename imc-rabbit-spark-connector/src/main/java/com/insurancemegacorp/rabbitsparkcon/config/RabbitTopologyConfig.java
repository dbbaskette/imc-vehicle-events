package com.insurancemegacorp.rabbitsparkcon.config;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class RabbitTopologyConfig {

    public static final String RAW_FOR_SPARK_DESTINATION = "telematics_raw_for_spark";

    @Bean
    public TopicExchange rawForSparkExchange() {
        return new TopicExchange(RAW_FOR_SPARK_DESTINATION, true, false);
    }

    @Bean
    public Queue rawForSparkQueue() {
        return new Queue(RAW_FOR_SPARK_DESTINATION, true);
    }

    @Bean
    public Binding bindRawForSparkQueue(Queue rawForSparkQueue, TopicExchange rawForSparkExchange) {
        return BindingBuilder.bind(rawForSparkQueue).to(rawForSparkExchange).with("#");
    }
}


