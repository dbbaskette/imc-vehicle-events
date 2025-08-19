# Custom JDBC Consumer - Quick Reference

## 🚀 **Stream Deployment Commands**

### Register Applications (if not auto-registered)
```bash
app register --name imc-jdbc-consumer --type sink --uri https://github.com/dbbaskette/imc-vehicle-events/releases/download/v1.0.0/imc-jdbc-consumer-1.0.0.jar
```

### Deploy Updated Streams
```bash
# Deploy all streams with custom JDBC consumer
stream deploy --name vehicle-events-to-jdbc --properties-file telemetry-streams.yml

# Or deploy individual stream
stream create --name vehicle-events-to-jdbc --definition ":vehicle_events > imc-jdbc-consumer"
stream deploy --name vehicle-events-to-jdbc
```

## 📊 **Monitoring Endpoints**

### Health Check
```bash
curl http://imc-jdbc-consumer-app-url/actuator/health
```

### Prometheus Metrics
```bash
curl http://imc-jdbc-consumer-app-url/actuator/prometheus | grep jdbc_consumer
```

### Application Info
```bash
curl http://imc-jdbc-consumer-app-url/actuator/info
```

## 🎯 **Key Metrics to Monitor**

### Throughput Metrics
```promql
# Messages per second
rate(jdbc_consumer_messages_total[5m])

# Success rate percentage
rate(jdbc_consumer_messages_success[5m]) / rate(jdbc_consumer_messages_total[5m]) * 100
```

### Error Metrics
```promql
# Error rate by type
rate(jdbc_consumer_messages_error[5m])

# Data quality issues
rate(jdbc_consumer_null_parameters_total[5m])
```

### Performance Metrics
```promql
# Processing duration percentiles
histogram_quantile(0.95, rate(jdbc_consumer_message_duration_bucket[5m]))
histogram_quantile(0.99, rate(jdbc_consumer_message_duration_bucket[5m]))
```

## ⚙️ **Configuration Quick Reference**

### Essential Properties
```yaml
# Core JDBC Configuration
app.imc-jdbc-consumer.jdbc.consumer.table-name: "vehicle_events"
app.imc-jdbc-consumer.jdbc.consumer.batch-size: "10"
app.imc-jdbc-consumer.jdbc.consumer.idle-timeout: "5000"

# Enhanced Features
app.imc-jdbc-consumer.jdbc.consumer.enable-metrics: "true"
app.imc-jdbc-consumer.jdbc.consumer.enable-retry: "true"
app.imc-jdbc-consumer.jdbc.consumer.max-retry-attempts: "3"
```

### Database Connection
```yaml
app.imc-jdbc-consumer.spring.datasource.url: "jdbc:postgresql://host:5432/db"
app.imc-jdbc-consumer.spring.datasource.username: "user"
app.imc-jdbc-consumer.spring.datasource.password: "password"
```

### Monitoring Configuration
```yaml
app.imc-jdbc-consumer.management.endpoints.web.exposure.include: "health,metrics,prometheus"
app.imc-jdbc-consumer.management.metrics.export.prometheus.enabled: "true"
```

## 🔧 **Troubleshooting Commands**

### Check Application Status
```bash
# List all apps
app list

# Check app info
app info --name imc-jdbc-consumer --type sink
```

### Stream Status
```bash
# List streams
stream list

# Check stream status
stream info --name vehicle-events-to-jdbc

# View stream logs
runtime apps --name vehicle-events-to-jdbc
```

### Database Connection Test
```bash
# Check health endpoint for database status
curl http://app-url/actuator/health | jq '.components.db'

# View datasource metrics
curl http://app-url/actuator/metrics/hikaricp.connections.active
```

## 🚨 **Common Issues & Solutions**

### Issue: Application Won't Start
**Check:**
```bash
# Verify JAR is accessible
app info --name imc-jdbc-consumer --type sink

# Check deployment logs
cf logs imc-jdbc-consumer-app-name --recent
```

### Issue: No Messages Being Processed
**Check:**
```bash
# Verify queue binding
curl http://app-url/actuator/health | jq '.components.rabbit'

# Check message metrics
curl http://app-url/actuator/metrics/jdbc_consumer_messages_total
```

### Issue: Database Connection Failures
**Check:**
```bash
# Database health
curl http://app-url/actuator/health | jq '.components.db'

# Connection pool status
curl http://app-url/actuator/metrics/hikaricp.connections
```

## 📈 **Performance Tuning**

### Batch Size Optimization
```yaml
# High throughput (larger batches)
app.imc-jdbc-consumer.jdbc.consumer.batch-size: "50"
app.imc-jdbc-consumer.jdbc.consumer.idle-timeout: "10000"

# Low latency (smaller batches)
app.imc-jdbc-consumer.jdbc.consumer.batch-size: "1"
app.imc-jdbc-consumer.jdbc.consumer.idle-timeout: "1000"
```

### Memory Tuning
```yaml
deployer.imc-jdbc-consumer.memory: "2048M"
deployer.imc-jdbc-consumer.cloudfoundry.env.JAVA_OPTS: "-Xmx1536m -Xms512m"
```

## 🔄 **Rollback Plan**

If issues arise, rollback to standard JDBC sink:
```yaml
# 1. Update stream definition
- name: "vehicle-events-to-jdbc"
  definition: ":vehicle_events > vehicle-events-sink: jdbc"

# 2. Add standard JDBC configuration
app.vehicle-events-sink.jdbc.consumer.table-name: "vehicle_events"
# ... other standard JDBC properties
```

## 📞 **Support Information**

### Log Locations
- **Application Logs**: `/actuator/loggers`
- **CF Logs**: `cf logs imc-jdbc-consumer-app-name`
- **SCDF Logs**: SCDF Dashboard → Runtime → Applications

### Key Log Patterns
```bash
# Success pattern
grep "Successfully processed" application.log

# Error pattern  
grep "Error processing message" application.log

# Retry pattern
grep "Retrying message" application.log
```

This quick reference provides everything needed to deploy, monitor, and troubleshoot the custom JDBC consumer in production environments.
