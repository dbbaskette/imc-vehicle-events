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
    public static final String RAW_FOR_SPARK_GROUPED_QUEUE = "telematics_raw_for_spark.telematics_raw_for_spark-group";

    @Bean
    public TopicExchange rawForSparkExchange() {
        return new TopicExchange(RAW_FOR_SPARK_DESTINATION, true, false);
    }

    @Bean
    public Queue rawForSparkQueue() {
        return new Queue(RAW_FOR_SPARK_GROUPED_QUEUE, true);
    }

    @Bean
    public Binding bindRawForSparkQueue(Queue rawForSparkQueue, TopicExchange rawForSparkExchange) {
        return BindingBuilder.bind(rawForSparkQueue).to(rawForSparkExchange).with("#");
    }
}


