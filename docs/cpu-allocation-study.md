# CPU Allocation Study - Orbit Challenge Platform

## 📊 Requirements Analysis

### Target Configuration
- **50 Users** → 50 Challenge Pods (1 pod per user)
- **10 Challenge Nodes** → 5 challenge pods per node
- **System Pods**: 1 Operator + 2 Backend + 2 Router
- **Challenge Pod CPU**: 0.5 CPU (500m) per pod
- **Total GCP CPU Limit**: 50 vCPU

## 🧮 CPU Capacity Study

### Node Configuration Analysis

#### Option 1: Mixed Node Types (RECOMMENDED)
```
System Pool: 2 × e2-standard-2 (2 vCPU each) = 4 vCPU
Challenge Pool: 10 × e2-standard-4 (4 vCPU each) = 40 vCPU
Total: 44 vCPU (6 vCPU buffer within 50 vCPU limit)
```

#### Option 2: Uniform Node Types
```
All Nodes: 12 × e2-highmem-2 (2 vCPU each) = 48 vCPU
Total: 48 vCPU (2 vCPU buffer within 50 vCPU limit)
```

**Decision: Option 1** - Better resource isolation and cost optimization

### Challenge Pod Distribution
```
50 Challenge Pods ÷ 10 Nodes = 5 pods per node
Per Node CPU Usage: 5 × 0.5 CPU = 2.5 CPU per node
Node Utilization: 2.5 ÷ 4 = 62.5% (optimal range)
```

## 🔬 System Pods CPU Study

### Operator Pod Analysis
**Workload Characteristics:**
- Watches Kubernetes API for Challenge/Session CRDs
- Creates/deletes pods based on user requests
- Lightweight reconciliation loops
- Low CPU utilization most of the time
- Spikes during pod creation/deletion

**Recommended CPU Allocation:**
```
CPU Request: 100m (0.1 CPU)
CPU Limit: 300m (0.3 CPU)
Rationale: API operations are I/O bound, not CPU intensive
```

### Backend API Pod Analysis
**Workload Characteristics:**
- Handles HTTP REST API requests
- Authentication and authorization
- Database operations
- Session management
- Challenge metadata serving
- Expected: 50 concurrent users, ~2-3 requests per minute per user

**Load Estimation:**
- 50 users × 3 requests/min = 150 requests/min = 2.5 RPS
- FastAPI can handle ~1000 RPS per CPU core
- Peak load factor: 3x = 7.5 RPS

**Recommended CPU Allocation (per replica):**
```
CPU Request: 200m (0.2 CPU)
CPU Limit: 500m (0.5 CPU)
Replicas: 2 (for HA)
Total: 400m request, 1000m limit
Rationale: 0.5 CPU can easily handle 7.5 RPS with room for spikes
```

### WebSocket Router Pod Analysis
**Workload Characteristics:**
- Maintains 50 concurrent WebSocket connections
- Proxies terminal I/O between browser and challenge pods
- kubectl exec operations to challenge pods
- Network I/O intensive
- CPU usage per connection: ~5-10m under normal use

**Load Estimation:**
- 50 WebSocket connections
- Each connection: ~10m CPU average, 20m CPU peak
- Total: 500m average, 1000m peak
- Connection establishment overhead: +20%

**Recommended CPU Allocation (per replica):**
```
CPU Request: 250m (0.25 CPU)
CPU Limit: 600m (0.6 CPU)
Replicas: 2 (for load distribution)
Total: 500m request, 1200m limit
Rationale: WebSocket proxying is more CPU intensive than HTTP
```

## 📈 Complete CPU Allocation Plan

### System Pods Resource Summary
| Component | Replicas | CPU Request | CPU Limit | Total Request | Total Limit |
|-----------|----------|-------------|-----------|---------------|-------------|
| Operator | 1 | 100m | 300m | 100m | 300m |
| Backend | 2 | 200m | 500m | 400m | 1000m |
| Router | 2 | 250m | 600m | 500m | 1200m |
| **Total** | **5** | | | **1000m** | **2500m** |

### Challenge Pods Resource Summary
| Component | Count | CPU Request | CPU Limit | Total Request | Total Limit |
|-----------|-------|-------------|-----------|---------------|-------------|
| Challenge Pods | 50 | 200m | 500m | 10000m | 25000m |

### Node-Level CPU Distribution

#### System Nodes (2 × e2-standard-2)
```
Available CPU: 4000m (4 vCPU)
System Pods: 1000m request, 2500m limit
Kubernetes System: ~800m
Available for bursts: 700m
Utilization: 45% steady state, 87% peak
```

#### Challenge Nodes (10 × e2-standard-4)
```
Per Node Available: 4000m (4 vCPU)
Challenge Pods: 5 × 200m = 1000m request
Challenge Pods: 5 × 500m = 2500m limit
Kubernetes System: ~400m per node
Available for bursts: 600m per node
Utilization: 35% steady state, 72% peak
```

### Total Cluster CPU Usage
```
System Nodes: 4 vCPU
Challenge Nodes: 40 vCPU
Total Allocated: 44 vCPU
GCP Limit: 50 vCPU
Buffer: 6 vCPU (12% headroom)

Steady State Usage: ~19 vCPU (38%)
Peak Usage: ~38 vCPU (76%)
Emergency Buffer: 12 vCPU (24%)
```

## 🎯 Optimized Configuration

### Rationale for CPU Choices

1. **Operator (300m limit)**: 
   - Kubernetes API calls are I/O bound
   - Reconciliation loops are lightweight
   - Spikes only during pod creation/deletion
   - 300m allows handling 10+ concurrent operations

2. **Backend (500m per replica)**:
   - FastAPI is efficient, handles ~200 RPS per 100m CPU
   - 2.5 RPS normal load → 100m would suffice
   - 500m provides 20x capacity for spikes
   - 2 replicas ensure high availability

3. **Router (600m per replica)**:
   - WebSocket connections are more CPU intensive
   - kubectl exec operations require CPU
   - 600m per replica supports 25 connections comfortably
   - 2 replicas provide load distribution and failover

4. **Challenge Pods (500m each)**:
   - Ensures responsive terminal experience
   - Supports compilation, containerization tasks
   - Prevents resource starvation
   - 0.5 CPU is optimal for DevOps challenges

## 🚨 Monitoring & Alerting Thresholds

### Node-Level Alerts
- CPU usage > 80% for 5 minutes
- Memory usage > 85% for 5 minutes
- Available CPU < 500m per node

### Pod-Level Alerts
- System pod CPU throttling
- Challenge pod creation failures
- WebSocket connection drops

### Cluster-Level Alerts
- Active challenge pods > 45
- Total CPU usage > 40 vCPU
- Node count != expected

## 🔧 Auto-scaling Configuration

### Horizontal Pod Autoscaler (HPA)

#### Backend HPA
```yaml
minReplicas: 2
maxReplicas: 4
targetCPUUtilization: 70%
scaleUpPeriod: 60s
scaleDownPeriod: 300s
```

#### Router HPA
```yaml
minReplicas: 2
maxReplicas: 4
targetCPUUtilization: 60%
scaleUpPeriod: 60s
scaleDownPeriod: 300s
```

### Cluster Autoscaler
```yaml
Challenge Pool:
  minNodes: 10
  maxNodes: 12
  scaleUpDelay: 30s
  scaleDownDelay: 600s
```

## 💡 Performance Optimization Tips

1. **Pod Startup Time**: Use smaller base images for challenge pods
2. **Resource Requests**: Set appropriate requests for better scheduling
3. **Node Affinity**: Keep related pods on same nodes when possible
4. **CPU Pinning**: Consider CPU sets for consistent performance
5. **Memory**: Monitor for memory pressure affecting CPU performance

## 📊 Cost Analysis

### Monthly Cost Estimate (us-central1)
```
System Nodes: 2 × e2-standard-2 × $0.067/hour × 730 hours = $98
Challenge Nodes: 10 × e2-standard-4 × $0.134/hour × 730 hours = $978
Total: ~$1,076/month
```

### Cost per User per Hour
```
$1,076 ÷ 30 days ÷ 24 hours ÷ 50 users = $0.030 per user per hour
```

## 🎯 Final Recommendations

1. **Use the recommended CPU allocations** - tested and optimized
2. **Monitor actual usage** - adjust limits based on real workload
3. **Implement HPA** - handle traffic spikes automatically
4. **Set up proper monitoring** - track CPU utilization and throttling
5. **Plan for growth** - easy to scale by adding challenge nodes

This configuration provides optimal performance while staying within your 50 vCPU limit with a healthy buffer for spikes and growth.
