package com.insurancemegacorp.jdbcconsumer;

import java.util.Map;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Enhanced configuration properties for the custom JDBC consumer.
 * 
 * Based on Spring Functions Catalog JDBC consumer but with additional
 * properties for metrics and monitoring.
 */
@ConfigurationProperties("jdbc.consumer")
public class JdbcConsumerProperties {

    @Autowired
    private ShorthandMapConverter shorthandMapConverter;

    /**
     * The name of the table to write into.
     */
    private String tableName = "messages";

    /**
     * The comma separated colon-based pairs of column names and SpEL expressions for
     * values to insert/update. Names are used at initialization time to issue the DDL.
     */
    private String columns = "payload:payload.toString()";

    /**
     * 'true', 'false' or the location of a custom initialization script for the table.
     */
    private String initialize = "false";

    /**
     * Threshold in number of messages when data will be flushed to database table.
     */
    private int batchSize = 1;

    /**
     * Idle timeout in milliseconds when data is automatically flushed to database table.
     */
    private long idleTimeout = -1L;

    /**
     * Enable detailed metrics collection (default: true).
     */
    private boolean enableMetrics = true;

    /**
     * Metrics prefix for Prometheus metrics (default: "jdbc_consumer").
     */
    private String metricsPrefix = "jdbc_consumer";

    /**
     * Enable error retry logic (default: true).
     */
    private boolean enableRetry = true;

    /**
     * Maximum number of retry attempts (default: 3).
     */
    private int maxRetryAttempts = 3;

    private Map<String, String> columnsMap;

    // Getters and setters
    public String getTableName() {
        return this.tableName;
    }

    public void setTableName(String tableName) {
        this.tableName = tableName;
    }

    public String getColumns() {
        return this.columns;
    }

    public void setColumns(String columns) {
        this.columns = columns;
    }

    public String getInitialize() {
        return this.initialize;
    }

    public void setInitialize(String initialize) {
        this.initialize = initialize;
    }

    public int getBatchSize() {
        return this.batchSize;
    }

    public void setBatchSize(int batchSize) {
        this.batchSize = batchSize;
    }

    public long getIdleTimeout() {
        return this.idleTimeout;
    }

    public void setIdleTimeout(long idleTimeout) {
        this.idleTimeout = idleTimeout;
    }

    public boolean isEnableMetrics() {
        return enableMetrics;
    }

    public void setEnableMetrics(boolean enableMetrics) {
        this.enableMetrics = enableMetrics;
    }

    public String getMetricsPrefix() {
        return metricsPrefix;
    }

    public void setMetricsPrefix(String metricsPrefix) {
        this.metricsPrefix = metricsPrefix;
    }

    public boolean isEnableRetry() {
        return enableRetry;
    }

    public void setEnableRetry(boolean enableRetry) {
        this.enableRetry = enableRetry;
    }

    public int getMaxRetryAttempts() {
        return maxRetryAttempts;
    }

    public void setMaxRetryAttempts(int maxRetryAttempts) {
        this.maxRetryAttempts = maxRetryAttempts;
    }

    Map<String, String> getColumnsMap() {
        if (this.columnsMap == null) {
            this.columnsMap = this.shorthandMapConverter.convert(this.columns);
        }
        return this.columnsMap;
    }
}
