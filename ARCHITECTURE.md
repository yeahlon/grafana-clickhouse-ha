# Architecture Documentation

## System Overview

This setup provides a highly available Grafana deployment with a clustered ClickHouse backend, all orchestrated with Podman.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Client Requests                             │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │   HAProxy (Port 3000)  │
                    │   Load Balancer        │
                    │   + Health Checks      │
                    └────────────┬───────────┘
                                 │
                ┌────────────────┼────────────────┐
                │                │                │
                ▼                ▼                ▼
        ┌──────────┐     ┌──────────┐     ┌──────────┐
        │ Grafana-1│     │ Grafana-2│     │ Grafana-3│
        │ (3001)   │     │ (3002)   │     │ (3003)   │
        │ Stateless│     │ Stateless│     │ Stateless│
        └─────┬────┘     └─────┬────┘     └─────┬────┘
              │                │                │
              └────────────────┼────────────────┘
                               │
                ┌──────────────┴──────────────┐
                │                             │
                ▼                             ▼
        ┌──────────────┐          ┌─────────────────────┐
        │  PostgreSQL  │          │  ClickHouse Cluster │
        │  (Port 5432) │          │                     │
        │              │          │  ┌───────────────┐  │
        │  - Sessions  │          │  │ Shard 1       │  │
        │  - Users     │          │  │ ├─ CH-01 (R1) │  │
        │  - Dashboards│          │  │ └─ CH-02 (R2) │  │
        │  - Alerts    │          │  │               │  │
        └──────────────┘          │  │ Shard 2       │  │
                                  │  │ ├─ CH-03 (R1) │  │
                                  │  │ └─ CH-04 (R2) │  │
                                  │  └───────────────┘  │
                                  │                     │
                                  │  Ports: 8123, 9000  │
                                  └──────────┬──────────┘
                                             │
                                             ▼
                                  ┌─────────────────────┐
                                  │  ClickHouse Keeper  │
                                  │  (Coordination)     │
                                  │                     │
                                  │  ├─ Keeper-01       │
                                  │  ├─ Keeper-02       │
                                  │  └─ Keeper-03       │
                                  │                     │
                                  │  Quorum: 2/3        │
                                  └─────────────────────┘
```

## Components

### 1. HAProxy Load Balancer
- **Purpose**: Distributes incoming requests across Grafana instances
- **Features**:
  - Round-robin load balancing
  - Active health checks (`/api/health`)
  - Automatic failover
  - Statistics dashboard (port 8404)
- **Configuration**: `haproxy/haproxy.cfg`

### 2. Grafana Instances (3x)
- **Purpose**: Web UI for visualization and dashboarding
- **Configuration**: Stateless, horizontally scalable
- **Features**:
  - Shared state via PostgreSQL
  - Session persistence in database
  - Auto-install ClickHouse plugin
- **Ports**: 3001, 3002, 3003 (direct access for debugging)
- **Configuration**: `grafana/grafana.ini`

### 3. PostgreSQL Database
- **Purpose**: External database for Grafana metadata
- **Stores**:
  - User accounts and permissions
  - Dashboard definitions
  - Alert configurations
  - Session data
  - Data source configurations
- **Why**: Enables stateless Grafana instances for HA
- **Configuration**: `postgres/init.sql`

### 4. ClickHouse Cluster (4 nodes)
- **Purpose**: High-performance time-series database
- **Topology**:
  - 2 Shards (horizontal partitioning)
  - 2 Replicas per shard (redundancy)
  - 4 total nodes
- **Features**:
  - Automatic data replication
  - Distributed queries
  - High availability
  - Horizontal scalability
- **Ports**:
  - 8123: HTTP interface
  - 9000: Native protocol
  - 9009: Interserver communication
- **Configuration**: `clickhouse/config.xml`, `clickhouse/users.xml`

### 5. ClickHouse Keeper (3 nodes)
- **Purpose**: Distributed coordination for ClickHouse replication
- **Features**:
  - Replaces ZooKeeper
  - Consensus-based coordination
  - Quorum: 2/3 nodes required
  - Leader election
- **Configuration**: `clickhouse/keeper_config.xml`

## Data Flow

### Read Path
1. User accesses http://localhost:3000
2. HAProxy selects a healthy Grafana instance
3. Grafana authenticates user against PostgreSQL
4. User creates/views dashboards
5. Dashboard queries sent to ClickHouse cluster
6. ClickHouse routes query to appropriate shard
7. Results aggregated and returned to Grafana
8. Grafana renders visualization

### Write Path (ClickHouse)
1. Data inserted into ClickHouse (any node)
2. If using distributed table, data routed to correct shard
3. Data written to local table
4. ClickHouse Keeper coordinates replication
5. Data replicated to replica node
6. Acknowledgment returned to client

## High Availability Features

### Grafana Layer
- **Load Balancing**: HAProxy distributes load across 3 instances
- **Health Checks**: Unhealthy instances automatically removed from pool
- **Session Persistence**: Sessions stored in PostgreSQL, shared across all instances
- **Stateless Design**: No local state, any instance can handle any request
- **Horizontal Scaling**: Add more instances by updating docker-compose.yml

### Database Layer (PostgreSQL)
- **Single Point of Failure**: Current setup
- **Production Enhancement**: Use PostgreSQL replication (streaming/logical)
- **Recommendation**: Deploy PostgreSQL with primary/replica setup

### ClickHouse Layer
- **Sharding**: Data distributed across 2 shards
- **Replication**: Each shard has 2 replicas
- **Fault Tolerance**: Can lose 1 replica per shard without data loss
- **Read Scaling**: Queries distributed across replicas
- **Write Availability**: If one replica fails, writes continue to other replica

### Coordination Layer (ClickHouse Keeper)
- **Quorum**: Requires 2 out of 3 nodes
- **Fault Tolerance**: Can tolerate 1 node failure
- **Automatic Failover**: Leader election on failure

## Scalability

### Horizontal Scaling

#### Grafana
```bash
# Add grafana-4, grafana-5 to docker-compose.yml
# Update haproxy.cfg to include new backends
podman-compose up -d --scale grafana-1=5
```

#### ClickHouse
- Add more shards for increased write throughput
- Add more replicas for increased read throughput
- Rebalance data using ClickHouse tools

### Vertical Scaling
- Increase CPU/memory limits in docker-compose.yml
- Adjust ClickHouse cache sizes in config.xml
- Tune PostgreSQL connection pool

## Network Architecture

All services communicate on a dedicated bridge network (`grafana-net`):
- Isolated from external networks
- Service discovery via container names
- Only HAProxy, ClickHouse HTTP, and debug ports exposed to host

## Security Considerations

### Current Setup (Development)
- Default passwords (must be changed)
- No SSL/TLS
- All services in same network
- Root access to containers

### Production Recommendations
- Enable SSL/TLS for all connections
- Use secrets management (Vault, etc.)
- Network segmentation (separate backend network)
- Enable ClickHouse authentication and authorization
- Configure Grafana OAuth/SAML
- Regular security updates
- Firewall rules
- Non-root containers

## Monitoring

### Health Endpoints
- HAProxy: http://localhost:8404/stats
- Grafana: http://localhost:3000/api/health
- ClickHouse: http://localhost:8123/ping

### Metrics
- HAProxy: Request rate, backend health, response times
- Grafana: Built-in metrics endpoint
- ClickHouse: `system.*` tables for cluster health
- PostgreSQL: Connection pool, query performance

## Backup Strategy

### PostgreSQL
- Regular pg_dump of grafana database
- Point-in-time recovery with WAL archiving

### ClickHouse
- Use ClickHouse BACKUP command
- Snapshot volumes at filesystem level
- Export critical tables to S3/object storage

## Recovery Scenarios

### Single Grafana Instance Failure
- **Detection**: HAProxy health checks
- **Action**: Automatic removal from pool
- **Impact**: None (load distributed to healthy instances)
- **Recovery**: Restart failed instance

### Single ClickHouse Node Failure
- **Detection**: Keeper heartbeat failure
- **Action**: Queries routed to replica
- **Impact**: Minimal (temporary increased load on replica)
- **Recovery**: Restart node, data auto-syncs from replica

### PostgreSQL Failure
- **Impact**: All Grafana instances lose state
- **Recovery**: Restore from backup, restart Grafana instances
- **Mitigation**: Implement PostgreSQL HA (recommended)

### Complete Keeper Cluster Failure
- **Impact**: ClickHouse replication stops (reads/writes continue)
- **Recovery**: Restart Keeper cluster
- **Note**: Need quorum (2/3) for coordination

## Resource Requirements

### Minimum (Development)
- CPU: 4 cores
- RAM: 8 GB
- Disk: 20 GB

### Recommended (Production)
- CPU: 16+ cores
- RAM: 32+ GB
- Disk: SSD, 100+ GB
- Network: 1 Gbps+

## Performance Tuning

### ClickHouse
- Increase `max_memory_usage` for large queries
- Tune `max_threads` for query parallelism
- Adjust `merge_tree` settings for optimal merges
- Configure proper partitioning strategy

### Grafana
- Increase `max_concurrent_queries`
- Tune database connection pool
- Enable caching for dashboards

### HAProxy
- Adjust `maxconn` based on load
- Tune timeout values
- Enable HTTP/2 support
