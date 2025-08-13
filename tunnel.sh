#!/bin/bash

# Create SSH tunnel to access RabbitMQ AMQP port
# Usage: ./tunnel.sh

echo "Creating SSH tunnel to Cloud Foundry for RabbitMQ access..."
echo "This will map local port 15672 to the RabbitMQ AMQP port"
echo ""
echo "You'll need CF CLI and cf ssh access to create this tunnel."
echo ""
echo "First, deploy a simple app to CF that can access the RabbitMQ service:"
echo "  cf push tunnel-app --no-start"
echo "  cf bind-service tunnel-app your-rabbitmq-service"
echo "  cf start tunnel-app"
echo ""
echo "Then create the tunnel:"
echo "  cf ssh -L 15672:q-s0.rabbitmq-server.kdc01-dvs-lab-mgt-net-82.service-instance-cf986537-69cc-4107-8b66-5542481de9ba.bosh:5672 tunnel-app"
echo ""
echo "After the tunnel is active, use the local profile to connect via localhost:15672"