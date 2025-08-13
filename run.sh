#!/bin/bash

# Build and run script for IMC Vehicle Events
# Usage: ./run.sh [--cloud]

set -e

PROFILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --cloud)
      PROFILE="cloud"
      shift
      ;;
    --tunnel)
      PROFILE="tunnel"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--cloud|--tunnel]"
      echo "  --cloud    Run with cloud profile for direct Cloud Foundry RabbitMQ"
      echo "  --tunnel   Run with tunnel profile for SSH tunneled access"
      echo "  --help     Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

echo "Building application..."
mvn clean package -DskipTests

echo "Starting application..."
if [ -n "$PROFILE" ]; then
  echo "Using profile: $PROFILE"
  java -jar target/imc-vehicle-events-1.0.0-SNAPSHOT.jar --spring.profiles.active=$PROFILE
else
  echo "Using default profile"
  java -jar target/imc-vehicle-events-1.0.0-SNAPSHOT.jar
fi