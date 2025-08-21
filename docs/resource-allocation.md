# Resource Allocation Summary

## 🎯 Target Configuration
- **50 Challenge Pods** distributed across 10 nodes
- **Total CPU Limit**: 50 vCPUs available on GCP
- **System Pods**: Operator, Backend, WebSocket Router

## 📊 CPU & Memory Allocation

### Node Configuration
| Node Pool | Node Type | vCPU per Node | Nodes | Total vCPU | Purpose |
|-----------|-----------|---------------|--------|------------|---------|
| System Pool | e2-standard-2 | 2 | 2 | 4 | Operator, Backend, Router |
| Challenge Pool | e2-standard-4 | 4 | 10 | 40 | Challenge Pods |
| **Total** | | | **12** | **44** | **6 vCPU Buffer** |

### System Pods Resource Allocation

#### Orbit Operator
- **CPU**: 200m limit, 100m request
- **Memory**: 256Mi limit, 128Mi request
- **Replicas**: 1
- **Node**: System pool (with tolerations)

#### Backend API (FastAPI)
- **CPU**: 500m limit, 200m request (per replica)
- **Memory**: 512Mi limit, 256Mi request (per replica)
- **Replicas**: 2 (HPA: 2-4)
- **Node**: System pool (with tolerations)
- **Total Resources**: 1000m CPU, 1024Mi memory (base)

#### WebSocket Router
- **CPU**: 300m limit, 100m request (per replica)
- **Memory**: 256Mi limit, 128Mi request (per replica)
- **Replicas**: 2 (HPA: 2-5)
- **Node**: System pool (with tolerations)
- **Total Resources**: 600m CPU, 512Mi memory (base)

#### System Pod Summary
| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Replicas |
|-----------|-------------|-----------|----------------|--------------|----------|
| Operator | 100m | 200m | 128Mi | 256Mi | 1 |
| Backend | 400m | 1000m | 512Mi | 1024Mi | 2 |
| Router | 200m | 600m | 256Mi | 512Mi | 2 |
| **Total** | **700m** | **1800m** | **896Mi** | **1792Mi** | **5** |

### Challenge Pods Resource Allocation

#### Per Challenge Pod
- **CPU**: 500m limit, 200m request
- **Memory**: 1Gi limit, 256Mi request
- **Storage**: 5Gi ephemeral
- **TTL**: 30 minutes (1800 seconds)
- **Priority**: challenge-priority (500)

#### Challenge Pod Distribution
- **10 Nodes** × **5 Pods per Node** = **50 Challenge Pods**
- **Per Node**: 5 × 500m = 2.5 CPU limit per node
- **Total Challenge**: 50 × 500m = 25 CPU limit
- **Total Challenge**: 50 × 1Gi = 50Gi memory limit

#### Challenge Pod Summary
| Metric | Per Pod | Total (50 pods) | Per Node (5 pods) |
|--------|---------|-----------------|-------------------|
| CPU Request | 200m | 10 CPU | 1 CPU |
| CPU Limit | 500m | 25 CPU | 2.5 CPU |
| Memory Request | 256Mi | 12.5Gi | 1.25Gi |
| Memory Limit | 1Gi | 50Gi | 5Gi |

## 🔧 Resource Optimization

### Node Utilization
```
System Nodes (2 × e2-standard-2):
- Available: 4 vCPU, 8Gi memory
- Used: ~1.8 vCPU, ~1.8Gi memory
- Utilization: ~45% CPU, ~22% memory

Challenge Nodes (10 × e2-standard-4):
- Available: 40 vCPU, 160Gi memory
- Used: 25 vCPU (limit), 50Gi memory (limit)
- Utilization: ~62% CPU, ~31% memory
```

### CPU Budget Breakdown
```
Total GCP Limit: 50 vCPU
├── System Nodes: 4 vCPU
│   ├── Operator: 0.2 vCPU (limit)
│   ├── Backend: 1.0 vCPU (2 replicas × 0.5)
│   ├── Router: 0.6 vCPU (2 replicas × 0.3)
│   └── System Overhead: ~1.2 vCPU
├── Challenge Nodes: 40 vCPU
│   ├── Challenge Pods: 25 vCPU (50 pods × 0.5)
│   └── Node Overhead: ~15 vCPU
└── Buffer: 6 vCPU (12% headroom)
```

## 🎛️ Auto-scaling Configuration

### Horizontal Pod Autoscaler (HPA)

#### Backend HPA
```yaml
minReplicas: 2
maxReplicas: 4
targetCPUUtilization: 70%
targetMemoryUtilization: 80%
```

#### WebSocket Router HPA
```yaml
minReplicas: 2
maxReplicas: 5
targetCPUUtilization: 60%
targetMemoryUtilization: 70%
```

### Cluster Autoscaler
- **System Pool**: Fixed at 2 nodes (no autoscaling)
- **Challenge Pool**: 10-12 nodes (2 additional for scaling)

## 📈 Capacity Planning

### Current Capacity
- **Concurrent Users**: 50 (1 pod per user)
- **Peak Load**: Can handle brief spikes with HPA
- **Session Duration**: 30 minutes average

### Scaling Scenarios

#### Scale to 60 Users
- Add 2 more challenge nodes (e2-standard-4)
- Additional 8 vCPU needed
- Total: 52 vCPU (within reasonable limits)

#### Scale to 100 Users
- Add 10 more challenge nodes
- Additional 40 vCPU needed
- Total: 84 vCPU (would exceed current limit)
- **Recommendation**: Upgrade to larger node types or increase CPU quota

## 🔍 Monitoring & Alerts

### Key Metrics to Monitor
1. **Node CPU Utilization**: Should stay < 80%
2. **Pod Resource Usage**: Track actual vs requested
3. **Challenge Pod Count**: Should not exceed 50
4. **WebSocket Connections**: Monitor router load
5. **Session Duration**: Track actual vs TTL

### Recommended Alerts
- Node CPU > 85%
- Challenge pods > 45 (early warning)
- WebSocket connections > 40
- Pod creation failures
- Memory usage > 90%

## 💡 Optimization Recommendations

### Cost Optimization
1. **Use Preemptible Nodes**: Challenge pool uses preemptible instances
2. **Right-size Resources**: Monitor actual usage and adjust
3. **Implement Pod Bin Packing**: Use node affinity for better utilization
4. **Session Timeout**: Aggressive cleanup of idle sessions

### Performance Optimization
1. **Node Affinity**: Keep related pods on same nodes
2. **Resource Requests**: Set appropriate requests for scheduling
3. **Image Optimization**: Use smaller, cached container images
4. **Network Policies**: Minimize network overhead

### Reliability
1. **Pod Disruption Budgets**: Maintain service during upgrades
2. **Health Checks**: Comprehensive liveness/readiness probes
3. **Resource Quotas**: Prevent resource exhaustion
4. **Priority Classes**: Ensure system pods get priority

## 🚨 Emergency Procedures

### High Resource Usage
1. Check for runaway challenge pods
2. Scale down non-essential services
3. Increase node pool size temporarily
4. Implement emergency resource limits

### Node Failures
1. Cluster autoscaler will replace failed nodes
2. Challenge pods will be rescheduled
3. System pods have multiple replicas
4. Monitor session continuity

### Quota Exceeded
1. Clean up completed challenge pods
2. Reduce concurrent session limits
3. Implement user queuing system
4. Scale up infrastructure if needed
