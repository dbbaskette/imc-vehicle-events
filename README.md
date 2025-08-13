# IMC Vehicle Events

A Spring Cloud Stream application that consumes vehicle telemetry data from RabbitMQ and detects crash events.

## Features

- Consumes vehicle telemetry data from RabbitMQ queue `telematics_work_queue` with consumer group `crash-detection-group`
- Detects crash events based on G-force threshold (>5.0) or event type "CRASH"
- Separate handling for crash events vs normal telemetry data
- Dead letter queue support for failed message processing
- Configurable for both local development and Cloud Foundry deployment

## Prerequisites

- Java 21
- Maven 3.6+
- RabbitMQ (for local development)

## Setup

### 1. Configure Application Properties

Copy the template files and configure them for your environment:

```bash
# For local development
cp src/main/resources/application.yml.template src/main/resources/application.yml

# For cloud deployment  
cp src/main/resources/application-cloud.yml.template src/main/resources/application-cloud.yml

# For tunnel development
cp src/main/resources/application-tunnel.yml.template src/main/resources/application-tunnel.yml
```

Edit the copied files to set your specific RabbitMQ connection details.

### 2. Build the Application

```bash
# Using Maven wrapper (recommended)
./mvnw clean package

# Or using system Maven
mvn clean package
```

## Running the Application

### Local Development
```bash
./run.sh
```

### With Cloud Profile
```bash
./run.sh --cloud
```

### With Tunnel Profile
```bash
./run.sh --tunnel
```

### Cloud Foundry Deployment
```bash
./mvnw clean package
cf push -f manifest.yml
```

## Message Format

The consumer expects JSON messages with the following structure:

```json
{
  "vehicle_id": "string",
  "timestamp": "2023-01-01T12:00:00",
  "speed": 65.5,
  "acceleration": 2.3,
  "g_force": 1.2,
  "latitude": 40.7128,
  "longitude": -74.0060,
  "heading": 180.0,
  "event_type": "NORMAL"
}
```

## Crash Detection

Crash events are detected when:
- G-force > 5.0 G
- Event type is "CRASH"

When a crash is detected, the application logs detailed crash information including location and vehicle dynamics.

## Configuration Templates

The application uses template files for configuration:

- `application.yml.template` - Local development with environment variable defaults
- `application-cloud.yml.template` - Cloud Foundry deployment configuration
- `application-tunnel.yml.template` - SSH tunnel configuration for development

These templates use environment variables for sensitive configuration values. The actual `application*.yml` files are ignored by git to prevent accidentally committing secrets.