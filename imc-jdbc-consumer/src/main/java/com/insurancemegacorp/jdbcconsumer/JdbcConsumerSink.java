package com.insurancemegacorp.jdbcconsumer;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.util.Map;
import java.util.Set;
import java.util.function.Consumer;

/**
 * Simple JDBC Consumer Sink - matches HdfsSink pattern exactly.
 * 
 * This class implements Consumer<String> directly and is registered as a @Component,
 * following the exact same pattern as the working HdfsSink.
 */
@Component
public class JdbcConsumerSink implements Consumer<String> {
    private static final Logger log = LoggerFactory.getLogger(JdbcConsumerSink.class);
    
    private final MeterRegistry meterRegistry;
    private final JdbcConsumerProperties properties;
    private final ObjectMapper objectMapper = new ObjectMapper();
    private NamedParameterJdbcTemplate jdbcTemplate;
    
    @Autowired
    private DataSource dataSource;

    public JdbcConsumerSink(MeterRegistry meterRegistry, JdbcConsumerProperties properties) {
        this.meterRegistry = meterRegistry;
        this.properties = properties;
    }

    @Override
    public void accept(String jsonMessage) {
        try {
            log.info("JDBC Consumer Sink received message: {}", 
                    jsonMessage.substring(0, Math.min(100, jsonMessage.length())) + "...");
            
            // Initialize JDBC template if needed
            if (jdbcTemplate == null) {
                jdbcTemplate = new NamedParameterJdbcTemplate(dataSource);
            }
            
            // Parse JSON message
            Map<String, Object> data = objectMapper.readValue(jsonMessage, Map.class);
            
            // Insert into database
            insertIntoDatabase(data);
            
            // Record success metrics
            if (properties.isEnableMetrics()) {
                meterRegistry.counter(properties.getMetricsPrefix() + "_messages_processed_total",
                                    "table", properties.getTableName()).increment();
            }
            
            log.debug("Successfully processed message for table: {}", properties.getTableName());
            
        } catch (Exception e) {
            log.error("Error processing message in JDBC consumer sink: {}", e.getMessage(), e);
            
            // Record error metrics
            if (properties.isEnableMetrics()) {
                meterRegistry.counter(properties.getMetricsPrefix() + "_messages_failed_total",
                                    "table", properties.getTableName(),
                                    "error", e.getClass().getSimpleName()).increment();
            }
            
            throw new RuntimeException("Failed to process message", e);
        }
    }

    private void insertIntoDatabase(Map<String, Object> data) {
        // Generate SQL
        String sql = generateInsertSql();
        
        // Map data to column parameters
        MapSqlParameterSource parameterSource = new MapSqlParameterSource();
        Map<String, String> columnMappings = properties.getColumnsMap();
        
        for (Map.Entry<String, String> entry : columnMappings.entrySet()) {
            String columnName = entry.getKey();
            String jsonKey = entry.getValue();
            Object value = data.get(jsonKey);
            parameterSource.addValue(columnName, value);
        }

        // Execute insert
        jdbcTemplate.update(sql, parameterSource);
        
        log.debug("Inserted record into table: {}", properties.getTableName());
    }

    private String generateInsertSql() {
        Set<String> columns = properties.getColumnsMap().keySet();
        StringBuilder sql = new StringBuilder("INSERT INTO ");
        sql.append(properties.getTableName()).append(" (");
        
        StringBuilder values = new StringBuilder(" VALUES (");
        boolean first = true;
        
        for (String column : columns) {
            if (!first) {
                sql.append(", ");
                values.append(", ");
            }
            sql.append(column);
            values.append(":").append(column);
            first = false;
        }
        
        sql.append(")").append(values).append(")");
        
        log.info("Generated SQL for table '{}': {}", properties.getTableName(), sql.toString());
        return sql.toString();
    }
}
