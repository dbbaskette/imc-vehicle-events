# IMC JDBC Consumer

Custom JDBC Consumer with Prometheus metrics and Service Registry integration for Insurance Megacorp's vehicle events processing pipeline.

## Features

### 🚀 Enhanced Capabilities
- **Prometheus Metrics**: Comprehensive monitoring with custom metrics
- **Service Registry**: Eureka client for Cloud Foundry service discovery
- **Batch Processing**: Configurable batch sizes and idle timeouts
- **Error Handling**: Retry logic and detailed error tracking
- **Performance Monitoring**: Message processing duration and throughput metrics

### 📊 Metrics Exposed
- `jdbc_consumer_messages_total` - Total messages processed
- `jdbc_consumer_messages_success` - Successfully processed messages
- `jdbc_consumer_messages_error` - Failed messages with error classification
- `jdbc_consumer_message_duration` - Processing time per message
- `jdbc_consumer_null_parameters_total` - Parameters that couldn't be extracted

## Configuration

### Basic JDBC Configuration
```yaml
jdbc:
  consumer:
    table-name: vehicle_events
    columns: "policy_id:policy_id,vehicle_id:vehicle_id,driver_id:driver_id,..."
    batch-size: 10
    idle-timeout: 5000
    initialize: false
```

### Enhanced Features
```yaml
jdbc:
  consumer:
    enable-metrics: true
    metrics-prefix: jdbc_consumer
    enable-retry: true
    max-retry-attempts: 3
```

### Database Connection
```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/vehicle_events
    username: postgres
    password: password
    driver-class-name: org.postgresql.Driver
```

## Usage in SCDF

### Registration
```bash
# Register the JAR with SCDF
app register --name imc-jdbc-consumer --type sink --uri file:///path/to/imc-jdbc-consumer-1.0.0.jar
```

### Stream Definition
```bash
# Create stream using the custom consumer
stream create --name vehicle-events-to-db --definition ":vehicle_events > imc-jdbc-consumer"
```

### Deployment Properties
```yaml
deployment_properties:
  imc-jdbc-consumer:
    app.imc-jdbc-consumer.spring.datasource.url: "jdbc:postgresql://dbhost:5432/vehicle_events"
    app.imc-jdbc-consumer.spring.datasource.username: "veh_user"
    app.imc-jdbc-consumer.spring.datasource.password: "***REDACTED***"
    app.imc-jdbc-consumer.jdbc.consumer.table-name: "vehicle_events"
    app.imc-jdbc-consumer.jdbc.consumer.batch-size: "10"
    app.imc-jdbc-consumer.jdbc.consumer.enable-metrics: "true"
```

## Monitoring

### Health Check
```bash
curl http://localhost:8080/actuator/health
```

### Metrics
```bash
curl http://localhost:8080/actuator/prometheus
```

### Key Metrics to Monitor
- **Throughput**: `jdbc_consumer_messages_total` rate
- **Error Rate**: `jdbc_consumer_messages_error` / `jdbc_consumer_messages_total`
- **Processing Time**: `jdbc_consumer_message_duration` percentiles
- **Data Quality**: `jdbc_consumer_null_parameters_total` rate

## Advantages Over Standard JDBC Sink

1. **Enhanced Monitoring**: Rich Prometheus metrics for production observability
2. **Service Discovery**: Automatic registration with Eureka for Cloud Foundry
3. **Better Error Handling**: Detailed error classification and retry logic
4. **Performance Insights**: Message processing duration and batch efficiency metrics
5. **Production Ready**: Comprehensive logging, health checks, and monitoring endpoints

## Development

### Building
```bash
mvn clean package
```

### Testing
```bash
mvn test
```

### Local Development
Copy `application.yml.template` to `application.yml` and customize for your environment.

## Architecture Integration

This consumer integrates seamlessly with the existing telemetry processing pipeline:

```
telematics_exchange (fanout)
    ├── imc-hdfs-sink (all telemetry → HDFS)
    └── imc-telemetry-processor (accidents → vehicle_events → imc-jdbc-consumer → database)
```

The custom JDBC consumer provides production-grade database ingestion with comprehensive monitoring and service discovery capabilities.
