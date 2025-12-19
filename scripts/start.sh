#!/bin/bash

# Startup script for Grafana ClickHouse HA cluster

echo "Starting Grafana ClickHouse HA cluster..."

# Check if .env file exists
if [ ! -f .env ]; then
    echo "Error: .env file not found!"
    echo "Please copy .env.example to .env and configure your settings."
    exit 1
fi

# Start all services
podman-compose up -d

echo ""
echo "Waiting for services to start (this may take a few minutes)..."
sleep 10

echo ""
echo "Service Status:"
podman-compose ps

echo ""
echo "=== Access Information ==="
echo "Grafana (via Load Balancer): http://localhost:3000"
echo "HAProxy Stats: http://localhost:8404/stats (admin/admin)"
echo "ClickHouse HTTP: http://localhost:8123"
echo ""
echo "Run './scripts/health-check.sh' to verify all services are healthy."
