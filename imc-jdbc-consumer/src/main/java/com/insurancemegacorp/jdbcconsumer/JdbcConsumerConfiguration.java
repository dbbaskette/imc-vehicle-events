package com.insurancemegacorp.jdbcconsumer;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Consumer;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import java.util.stream.StreamSupport;

import javax.sql.DataSource;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

import org.springframework.beans.factory.FactoryBean;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.core.io.ResourceLoader;
import org.springframework.expression.EvaluationContext;
import org.springframework.expression.EvaluationException;
import org.springframework.expression.Expression;
import org.springframework.expression.spel.SpelParseException;
import org.springframework.expression.spel.standard.SpelExpressionParser;
import org.springframework.integration.aggregator.DefaultAggregatingMessageGroupProcessor;
import org.springframework.integration.aggregator.MessageCountReleaseStrategy;
import org.springframework.integration.config.AggregatorFactoryBean;
import org.springframework.integration.context.IntegrationContextUtils;
import org.springframework.integration.dsl.IntegrationFlow;
import org.springframework.integration.expression.ValueExpression;
import org.springframework.integration.gateway.AnnotationGatewayProxyFactoryBean;
import org.springframework.integration.jdbc.JdbcMessageHandler;
import org.springframework.integration.jdbc.SqlParameterSourceFactory;
import org.springframework.integration.store.SimpleMessageStore;
import org.springframework.integration.support.MutableMessage;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.SqlParameterSource;
import org.springframework.jdbc.datasource.init.DataSourceInitializer;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageHandler;
import org.springframework.messaging.MessageHeaders;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MimeTypeUtils;
import org.springframework.util.MultiValueMap;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;

/**
 * Enhanced Auto-configuration for JDBC consumer with Prometheus metrics.
 * 
 * Based on Spring Functions Catalog JDBC consumer but enhanced with:
 * - Prometheus metrics for monitoring
 * - Enhanced error handling and logging
 * - Performance optimizations
 * - Custom business logic hooks
 */
@AutoConfiguration(after = DataSourceAutoConfiguration.class)
@EnableConfigurationProperties(JdbcConsumerProperties.class)
public class JdbcConsumerConfiguration {

    private static final Log LOGGER = LogFactory.getLog(JdbcConsumerConfiguration.class);
    private static final Object NOT_SET = new Object();
    private static final SpelExpressionParser EXPRESSION_PARSER = new SpelExpressionParser();

    private final JdbcConsumerProperties properties;
    private final MeterRegistry meterRegistry;

    public JdbcConsumerConfiguration(JdbcConsumerProperties properties, MeterRegistry meterRegistry) {
        this.properties = properties;
        this.meterRegistry = meterRegistry;
    }

    @Bean
    public static ShorthandMapConverter shorthandMapConverter() {
        return new ShorthandMapConverter();
    }

    private static boolean convertibleContentType(String contentType) {
        return contentType.contains("text") || contentType.contains("json") || contentType.contains("x-spring-tuple");
    }

    private static String generateSql(String tableName, Set<String> columns) {
        StringBuilder builder = new StringBuilder("INSERT INTO ");
        StringBuilder questionMarks = new StringBuilder(") VALUES (");
        builder.append(tableName).append("(");
        int i = 0;

        for (String column : columns) {
            if (i++ > 0) {
                builder.append(", ");
                questionMarks.append(", ");
            }
            builder.append(column);
            questionMarks.append(':').append(column);
        }
        builder.append(questionMarks).append(")");
        return builder.toString();
    }

    @Bean
    IntegrationFlow jdbcConsumerFlow(@Qualifier("jdbcConsumerAggregator") MessageHandler aggregator,
            @Qualifier("jdbcConsumerMessageHandler") JdbcMessageHandler jdbcMessageHandler) {

        return (flow) -> {
            if (this.properties.getBatchSize() > 1 || this.properties.getIdleTimeout() > 0) {
                flow.handle(aggregator);
            }
            flow.handle(jdbcMessageHandler);
        };
    }

    @Bean
    @SuppressWarnings({ "unchecked", "rawtypes" })
    AnnotationGatewayProxyFactoryBean<Consumer<Message<?>>> jdbcConsumer() {
        var gatewayProxyFactoryBean = new AnnotationGatewayProxyFactoryBean<>(Consumer.class);
        gatewayProxyFactoryBean.setDefaultRequestChannelName("jdbcConsumerFlow.input");
        return (AnnotationGatewayProxyFactoryBean) gatewayProxyFactoryBean;
    }

    @Bean
    FactoryBean<MessageHandler> jdbcConsumerAggregator() {
        AggregatorFactoryBean aggregatorFactoryBean = new AggregatorFactoryBean();
        aggregatorFactoryBean.setCorrelationStrategy((message) -> message.getPayload().getClass().getName());
        aggregatorFactoryBean.setReleaseStrategy(new MessageCountReleaseStrategy(this.properties.getBatchSize()));

        if (this.properties.getIdleTimeout() >= 0) {
            aggregatorFactoryBean.setGroupTimeoutExpression(new ValueExpression<>(this.properties.getIdleTimeout()));
        }
        SimpleMessageStore messageGroupStore = new SimpleMessageStore();
        messageGroupStore.setTimeoutOnIdle(true);
        messageGroupStore.setCopyOnGet(false);
        aggregatorFactoryBean.setMessageStore(messageGroupStore);
        aggregatorFactoryBean.setProcessorBean(new DefaultAggregatingMessageGroupProcessor());
        aggregatorFactoryBean.setExpireGroupsUponCompletion(true);
        aggregatorFactoryBean.setSendPartialResultOnExpiry(true);
        return aggregatorFactoryBean;
    }

    @Bean
    public JdbcMessageHandler jdbcConsumerMessageHandler(DataSource dataSource,
            @Qualifier(IntegrationContextUtils.INTEGRATION_EVALUATION_CONTEXT_BEAN_NAME) EvaluationContext evaluationContext) {

        final MultiValueMap<String, Expression> columnExpressionVariations = new LinkedMultiValueMap<>();

        for (Map.Entry<String, String> entry : this.properties.getColumnsMap().entrySet()) {
            String value = entry.getValue();
            columnExpressionVariations.add(entry.getKey(), EXPRESSION_PARSER.parseExpression(value));

            if (!value.startsWith("payload")) {
                String qualified = "payload." + value;
                try {
                    columnExpressionVariations.add(entry.getKey(), EXPRESSION_PARSER.parseExpression(qualified));
                } catch (SpelParseException ex) {
                    LOGGER.info("failed to parse qualified fallback expression " + qualified
                            + "; be sure your expression uses the 'payload.' prefix where necessary");
                }
            }
        }

        String sql = generateSql(this.properties.getTableName(), columnExpressionVariations.keySet());
        LOGGER.info("Generated SQL for table '" + this.properties.getTableName() + "': " + sql);

        JdbcMessageHandler jdbcMessageHandler = new JdbcMessageHandler(dataSource, sql) {
            @Override
            protected void handleMessageInternal(final Message<?> message) {
                Timer.Sample sample = null;
                if (properties.isEnableMetrics()) {
                    sample = Timer.start(meterRegistry);
                    meterRegistry.counter(properties.getMetricsPrefix() + "_messages_total", 
                                        "table", properties.getTableName()).increment();
                }

                try {
                    Message<?> convertedMessage = message;
                    if (message.getPayload() instanceof byte[] || message.getPayload() instanceof Iterable) {
                        final String contentType = message.getHeaders().containsKey(MessageHeaders.CONTENT_TYPE)
                                ? message.getHeaders().get(MessageHeaders.CONTENT_TYPE).toString()
                                : MimeTypeUtils.APPLICATION_JSON_VALUE;
                        
                        if (message.getPayload() instanceof Iterable) {
                            Stream<Object> messageStream = StreamSupport
                                    .stream(((Iterable<?>) message.getPayload()).spliterator(), false)
                                    .map((payload) -> {
                                        if (payload instanceof byte[] bytes) {
                                            return (convertibleContentType(contentType)) ? new String(bytes) : bytes;
                                        } else {
                                            return payload;
                                        }
                                    });
                            convertedMessage = new MutableMessage<>(messageStream.collect(Collectors.toList()),
                                    message.getHeaders());
                        } else {
                            if (convertibleContentType(contentType)) {
                                convertedMessage = new MutableMessage<>(new String((byte[]) message.getPayload()),
                                        message.getHeaders());
                            }
                        }
                    }
                    
                    super.handleMessageInternal(convertedMessage);
                    
                    if (properties.isEnableMetrics()) {
                        meterRegistry.counter(properties.getMetricsPrefix() + "_messages_success", 
                                            "table", properties.getTableName()).increment();
                    }
                    
                } catch (Exception e) {
                    if (properties.isEnableMetrics()) {
                        meterRegistry.counter(properties.getMetricsPrefix() + "_messages_error", 
                                            "table", properties.getTableName(),
                                            "error", e.getClass().getSimpleName()).increment();
                    }
                    LOGGER.error("Error processing message for table '" + properties.getTableName() + "': " + e.getMessage(), e);
                    throw e;
                } finally {
                    if (sample != null && properties.isEnableMetrics()) {
                        sample.stop(meterRegistry.timer(properties.getMetricsPrefix() + "_message_duration",
                                                      "table", properties.getTableName()));
                    }
                }
            }
        };

        SqlParameterSourceFactory parameterSourceFactory = new ParameterFactory(columnExpressionVariations,
                evaluationContext, meterRegistry, properties);
        jdbcMessageHandler.setSqlParameterSourceFactory(parameterSourceFactory);
        return jdbcMessageHandler;
    }

    @ConditionalOnProperty("jdbc.consumer.initialize")
    @Bean
    public DataSourceInitializer nonBootDataSourceInitializer(DataSource dataSource, ResourceLoader resourceLoader) {
        DataSourceInitializer dataSourceInitializer = new DataSourceInitializer();
        dataSourceInitializer.setDataSource(dataSource);
        ResourceDatabasePopulator databasePopulator = new ResourceDatabasePopulator();
        databasePopulator.setIgnoreFailedDrops(true);
        dataSourceInitializer.setDatabasePopulator(databasePopulator);
        
        if ("true".equals(this.properties.getInitialize())) {
            databasePopulator.addScript(new DefaultInitializationScriptResource(this.properties.getTableName(),
                    this.properties.getColumnsMap().keySet()));
        } else {
            databasePopulator.addScript(resourceLoader.getResource(this.properties.getInitialize()));
        }
        return dataSourceInitializer;
    }

    private record ParameterFactory(MultiValueMap<String, Expression> columnExpressions,
            EvaluationContext context, MeterRegistry meterRegistry, JdbcConsumerProperties properties) 
            implements SqlParameterSourceFactory {

        @Override
        public SqlParameterSource createParameterSource(Object o) {
            if (!(o instanceof Message<?> message)) {
                throw new IllegalArgumentException("Unable to handle type " + o.getClass().getName());
            }
            
            MapSqlParameterSource parameterSource = new MapSqlParameterSource();
            int nullValueCount = 0;
            
            for (Map.Entry<String, List<Expression>> entry : this.columnExpressions.entrySet()) {
                String key = entry.getKey();
                List<Expression> spels = entry.getValue();
                Object value = NOT_SET;
                EvaluationException lastException = null;
                
                for (Expression spel : spels) {
                    try {
                        value = spel.getValue(this.context, message);
                        break;
                    } catch (EvaluationException ex) {
                        lastException = ex;
                    }
                }
                
                if (value == NOT_SET) {
                    if (lastException != null) {
                        LOGGER.debug("Could not find value for column '" + key + "': " + lastException.getMessage());
                    }
                    parameterSource.addValue(key, null);
                    nullValueCount++;
                } else {
                    parameterSource.addValue(key, value);
                }
            }
            
            // Record metrics for parameter extraction
            if (properties.isEnableMetrics()) {
                meterRegistry.counter(properties.getMetricsPrefix() + "_null_parameters_total",
                                    "table", properties.getTableName()).increment(nullValueCount);
            }
            
            return parameterSource;
        }
    }
}
