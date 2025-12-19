#!/bin/bash

# Health check script for all services

echo "=== Grafana ClickHouse HA Health Check ==="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_service() {
    local service=$1
    local url=$2
    
    if curl -s -f -o /dev/null "$url"; then
        echo -e "${GREEN}✓${NC} $service is healthy"
        return 0
    else
        echo -e "${RED}✗${NC} $service is unhealthy"
        return 1
    fi
}

check_container() {
    local container=$1
    
    if podman ps --filter "name=$container" --filter "status=running" --format "{{.Names}}" | grep -q "$container"; then
        echo -e "${GREEN}✓${NC} Container $container is running"
        return 0
    else
        echo -e "${RED}✗${NC} Container $container is not running"
        return 1
    fi
}

echo "--- Container Status ---"
check_container "postgres"
check_container "keeper-01"
check_container "keeper-02"
check_container "keeper-03"
check_container "clickhouse-01"
check_container "clickhouse-02"
check_container "clickhouse-03"
check_container "clickhouse-04"
check_container "grafana-1"
check_container "grafana-2"
check_container "grafana-3"
check_container "haproxy"

echo ""
echo "--- Service Health ---"

# Check PostgreSQL
if podman exec postgres pg_isready -U grafana > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} PostgreSQL is healthy"
else
    echo -e "${RED}✗${NC} PostgreSQL is unhealthy"
fi

# Check ClickHouse instances
for i in {1..4}; do
    if podman exec clickhouse-0$i clickhouse-client --query "SELECT 1" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} ClickHouse-0$i is healthy"
    else
        echo -e "${RED}✗${NC} ClickHouse-0$i is unhealthy"
    fi
done

# Check Grafana instances via HAProxy
check_service "HAProxy Load Balancer" "http://localhost:3000/api/health"
check_service "HAProxy Stats" "http://localhost:8404/stats"

# Check individual Grafana instances
check_service "Grafana-1" "http://localhost:3001/api/health"
check_service "Grafana-2" "http://localhost:3002/api/health"
check_service "Grafana-3" "http://localhost:3003/api/health"

# Check ClickHouse HTTP interface
check_service "ClickHouse HTTP" "http://localhost:8123/ping"

echo ""
echo "--- ClickHouse Cluster Status ---"

# Check cluster configuration
if podman exec clickhouse-01 clickhouse-client --query "SELECT cluster, shard_num, replica_num, host_name FROM system.clusters WHERE cluster = 'cluster_2S_2R' ORDER BY shard_num, replica_num" 2>/dev/null; then
    echo -e "${GREEN}ClickHouse cluster is configured${NC}"
else
    echo -e "${YELLOW}ClickHouse cluster check failed (might be starting)${NC}"
fi

echo ""
echo "=== Health Check Complete ==="
