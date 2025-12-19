# Quick Start Guide

## Prerequisites

Install Podman and Podman Compose:

### macOS
```bash
brew install podman podman-compose
podman machine init
podman machine start
```

### Linux
```bash
# Debian/Ubuntu
sudo apt-get install podman podman-compose

# RHEL/CentOS/Fedora
sudo dnf install podman podman-compose
```

## Deploy the Cluster

1. **Review and customize environment variables** (optional):
   ```bash
   vi .env
   ```

2. **Start all services**:
   ```bash
   ./scripts/start.sh
   ```
   
   Or manually:
   ```bash
   podman-compose up -d
   ```

3. **Wait for services to be ready** (2-3 minutes):
   ```bash
   watch podman-compose ps
   ```

4. **Verify deployment**:
   ```bash
   ./scripts/health-check.sh
   ```

## Access Services

- **Grafana UI**: http://localhost:3000
  - Username: `admin`
  - Password: `admin` (change on first login)

- **HAProxy Stats**: http://localhost:8404/stats
  - Username: `admin`
  - Password: `admin`

- **ClickHouse HTTP**: http://localhost:8123

## Configure ClickHouse Data Source in Grafana

1. Open Grafana at http://localhost:3000
2. Go to **Configuration** → **Data Sources** → **Add data source**
3. Search for "ClickHouse" and select it
4. Configure:
   - **Name**: ClickHouse
   - **Server address**: `clickhouse-01`
   - **Server port**: `9000`
   - **Protocol**: Native
   - **Username**: `default`
   - **Password**: `clickhouse_secure_password_456` (from .env)
   - **Database**: `default`
5. Click **Save & Test**

## Create Sample ClickHouse Table

```bash
# Connect to ClickHouse
podman exec -it clickhouse-01 clickhouse-client --password

# Create a replicated table on the cluster
CREATE TABLE metrics_local ON CLUSTER cluster_2S_2R
(
    timestamp DateTime,
    metric_name String,
    value Float64,
    host String
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/metrics', '{replica}')
PARTITION BY toYYYYMM(timestamp)
ORDER BY (metric_name, timestamp);

# Create distributed table
CREATE TABLE metrics ON CLUSTER cluster_2S_2R AS metrics_local
ENGINE = Distributed(cluster_2S_2R, default, metrics_local, rand());

# Insert sample data
INSERT INTO metrics VALUES 
    (now(), 'cpu_usage', 45.5, 'server1'),
    (now(), 'memory_usage', 78.2, 'server1'),
    (now(), 'disk_usage', 62.1, 'server1');

# Query the data
SELECT * FROM metrics ORDER BY timestamp DESC LIMIT 10;
```

## Verify High Availability

### Test Grafana Load Balancing
```bash
# Make multiple requests and see different Grafana instances responding
for i in {1..10}; do
  curl -s http://localhost:3000/api/health | grep -o '"database":[^,]*'
done
```

### Test ClickHouse Replication
```bash
# Insert data on one node
podman exec clickhouse-01 clickhouse-client --password --query \
  "INSERT INTO metrics VALUES (now(), 'test_metric', 99.9, 'test_host')"

# Query from another node - should see the replicated data
podman exec clickhouse-02 clickhouse-client --password --query \
  "SELECT * FROM metrics WHERE metric_name = 'test_metric'"
```

### Check Cluster Status
```bash
podman exec clickhouse-01 clickhouse-client --password --query \
  "SELECT cluster, shard_num, replica_num, host_name FROM system.clusters WHERE cluster = 'cluster_2S_2R'"
```

## Stop Services

```bash
podman-compose down
```

## Troubleshooting

### Services not starting
```bash
# Check logs
podman-compose logs -f

# Check specific service
podman-compose logs -f grafana-1
podman-compose logs -f clickhouse-01
```

### Reset everything
```bash
# Stop and remove all containers and volumes
podman-compose down -v

# Start fresh
./scripts/start.sh
```

### Check resource usage
```bash
podman stats
```

## Next Steps

- Configure SSL/TLS for production
- Set up backup schedules
- Configure monitoring and alerting
- Add more Grafana instances for scaling
- Customize ClickHouse retention policies
- Set up log aggregation
