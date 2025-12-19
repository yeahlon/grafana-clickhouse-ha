# Grafana High Availability Setup with ClickHouse Backend

A production-ready, high-availability Grafana deployment with ClickHouse cluster backend, orchestrated using Podman.

## Architecture

### Components

- **Grafana (3 instances)**: Stateless frontend instances for horizontal scaling
- **HAProxy**: Load balancer for distributing traffic across Grafana instances
- **PostgreSQL**: External database for Grafana sessions, users, and dashboards
- **ClickHouse Cluster (2 shards, 2 replicas)**: High-availability time-series backend
  - ClickHouse Server 1 (Shard 1, Replica 1)
  - ClickHouse Server 2 (Shard 1, Replica 2)
  - ClickHouse Server 3 (Shard 2, Replica 1)
  - ClickHouse Server 4 (Shard 2, Replica 2)
- **ClickHouse Keeper (3 instances)**: Distributed coordination service for ClickHouse replication

### Features

- ✅ Horizontal scaling for Grafana
- ✅ Stateless Grafana instances
- ✅ ClickHouse replication and sharding
- ✅ Load balancing with health checks
- ✅ Persistent storage for all stateful components
- ✅ Container orchestration with Podman

## Prerequisites

- Podman 4.0+
- Podman Compose 1.0+
- At least 8GB RAM
- 20GB available disk space

## Quick Start

1. **Clone and setup**:
   ```bash
   cd /path/to/grafana-clickhouse-ha
   cp .env.example .env
   ```

2. **Configure environment** (edit `.env` if needed):
   - Grafana admin credentials
   - PostgreSQL credentials
   - ClickHouse credentials

3. **Start all services**:
   ```bash
   podman-compose up -d
   ```

4. **Verify deployment**:
   ```bash
   ./scripts/health-check.sh
   ```

5. **Access Grafana**:
   - URL: http://localhost:3000
   - Default credentials: admin/admin (change on first login)

## Service Endpoints

| Service | Port | Description |
|---------|------|-------------|
| HAProxy (Grafana LB) | 3000 | Main Grafana access point |
| HAProxy Stats | 8404 | HAProxy statistics dashboard |
| Grafana Instance 1 | 3001 | Direct access (debugging) |
| Grafana Instance 2 | 3002 | Direct access (debugging) |
| Grafana Instance 3 | 3003 | Direct access (debugging) |
| ClickHouse HTTP | 8123 | ClickHouse HTTP interface |
| ClickHouse Native | 9000 | ClickHouse native protocol |
| PostgreSQL | 5432 | Grafana metadata database |

## Management Commands

### Start all services
```bash
podman-compose up -d
```

### Stop all services
```bash
podman-compose down
```

### View logs
```bash
# All services
podman-compose logs -f

# Specific service
podman-compose logs -f grafana-1
podman-compose logs -f clickhouse-01
```

### Scale Grafana instances
```bash
podman-compose up -d --scale grafana-1=5
```

### Restart a service
```bash
podman-compose restart grafana-1
```

### Check service status
```bash
podman-compose ps
```

## ClickHouse Cluster Configuration

The ClickHouse cluster is configured with:
- **2 shards** for horizontal data distribution
- **2 replicas per shard** for high availability
- **ClickHouse Keeper** for distributed coordination (replaces ZooKeeper)

### Creating a distributed table

```sql
-- On any ClickHouse instance
CREATE TABLE metrics_local ON CLUSTER '{cluster}'
(
    timestamp DateTime,
    metric_name String,
    value Float64,
    tags Map(String, String)
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/metrics', '{replica}')
PARTITION BY toYYYYMM(timestamp)
ORDER BY (metric_name, timestamp);

-- Distributed table
CREATE TABLE metrics ON CLUSTER '{cluster}' AS metrics_local
ENGINE = Distributed('{cluster}', default, metrics_local, rand());
```

## Grafana Configuration

### Data Source Setup

1. Log in to Grafana (http://localhost:3000)
2. Go to **Configuration** → **Data Sources** → **Add data source**
3. Select **ClickHouse**
4. Configure:
   - **Server**: clickhouse-01:9000 (or any ClickHouse node)
   - **Username**: default
   - **Password**: (from .env file)
   - **Database**: default

### High Availability Features

- **Session Storage**: PostgreSQL (shared across all instances)
- **Dashboard Storage**: PostgreSQL (shared across all instances)
- **User Management**: PostgreSQL (shared across all instances)
- **Load Balancing**: HAProxy with round-robin and health checks

## Monitoring

### HAProxy Stats Dashboard
- URL: http://localhost:8404/stats
- Monitor Grafana instance health and traffic distribution

### ClickHouse System Tables
```sql
-- Check cluster status
SELECT * FROM system.clusters WHERE cluster = 'cluster_2S_2R';

-- Check replication queue
SELECT * FROM system.replication_queue;

-- Check replicas status
SELECT * FROM system.replicas;
```

## Backup and Recovery

### PostgreSQL Backup
```bash
podman exec postgres pg_dump -U grafana grafana > backup_$(date +%Y%m%d).sql
```

### ClickHouse Backup
```bash
# Backup configuration
podman exec clickhouse-01 clickhouse-client --query="BACKUP DATABASE default TO Disk('backups', 'backup_$(date +%Y%m%d)')"
```

## Troubleshooting

### Grafana instances not starting
- Check PostgreSQL is running and accessible
- Verify database credentials in `.env`
- Check logs: `podman-compose logs grafana-1`

### ClickHouse replication issues
- Ensure all ClickHouse Keeper instances are running
- Check ClickHouse logs: `podman-compose logs clickhouse-01`
- Verify network connectivity between nodes

### Load balancer issues
- Check HAProxy stats: http://localhost:8404/stats
- Verify Grafana instances are healthy
- Review HAProxy logs: `podman-compose logs haproxy`

## Security Considerations

⚠️ **Production Deployment Checklist**:

- [ ] Change all default passwords in `.env`
- [ ] Enable TLS/SSL for all services
- [ ] Configure firewall rules
- [ ] Set up proper network isolation
- [ ] Enable ClickHouse authentication
- [ ] Configure Grafana OAuth/LDAP
- [ ] Regular backup schedules
- [ ] Monitor resource usage
- [ ] Set up log aggregation

## Scaling

### Horizontal Scaling (Add more Grafana instances)
```bash
# Edit docker-compose.yml to add grafana-4, grafana-5, etc.
# Update haproxy/haproxy.cfg to include new backends
podman-compose up -d
```

### Vertical Scaling (Increase resources)
Edit service definitions in `docker-compose.yml`:
```yaml
deploy:
  resources:
    limits:
      cpus: '2'
      memory: 4G
```

## License

MIT

## Contributing

Pull requests are welcome. For major changes, please open an issue first.
