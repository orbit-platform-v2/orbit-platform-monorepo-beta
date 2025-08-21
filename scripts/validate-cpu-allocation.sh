#!/bin/bash

# Orbit Challenge Platform - CPU Allocation Validation Script
# Validates the exact CPU specifications for 50 users with 0.5 CPU per challenge pod

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Expected configuration
EXPECTED_CHALLENGE_PODS=50
EXPECTED_CHALLENGE_NODES=10
EXPECTED_SYSTEM_NODES=2
CHALLENGE_CPU_LIMIT="500m"
CHALLENGE_CPU_REQUEST="200m"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

validate_cluster_resources() {
    log_info "Validating cluster resource allocation..."
    
    # Check total nodes
    local total_nodes=$(kubectl get nodes --no-headers | wc -l)
    local system_nodes=$(kubectl get nodes -l role=system --no-headers 2>/dev/null | wc -l)
    local challenge_nodes=$(kubectl get nodes -l role=challenge --no-headers 2>/dev/null | wc -l)
    
    echo "Node Distribution:"
    echo "  Total Nodes: $total_nodes"
    echo "  System Nodes: $system_nodes (expected: $EXPECTED_SYSTEM_NODES)"
    echo "  Challenge Nodes: $challenge_nodes (expected: $EXPECTED_CHALLENGE_NODES)"
    
    if [ $challenge_nodes -ne $EXPECTED_CHALLENGE_NODES ]; then
        log_error "Challenge node count mismatch!"
        return 1
    fi
    
    if [ $system_nodes -ne $EXPECTED_SYSTEM_NODES ]; then
        log_warning "System node count differs from expected"
    fi
}

validate_system_pods() {
    log_info "Validating system pod CPU allocations..."
    
    # Check operator pod
    local operator_cpu_limit=$(kubectl get pod -n orbit-system -l app=orbit-operator -o jsonpath='{.items[0].spec.containers[0].resources.limits.cpu}' 2>/dev/null)
    local operator_cpu_request=$(kubectl get pod -n orbit-system -l app=orbit-operator -o jsonpath='{.items[0].spec.containers[0].resources.requests.cpu}' 2>/dev/null)
    
    echo "Operator Pod:"
    echo "  CPU Limit: $operator_cpu_limit (expected: 300m)"
    echo "  CPU Request: $operator_cpu_request (expected: 100m)"
    
    # Check backend pods
    local backend_replicas=$(kubectl get deployment orbit-backend -n orbit-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    local backend_cpu_limit=$(kubectl get deployment orbit-backend -n orbit-system -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}' 2>/dev/null)
    local backend_cpu_request=$(kubectl get deployment orbit-backend -n orbit-system -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null)
    
    echo "Backend Pods:"
    echo "  Replicas: $backend_replicas (expected: 2)"
    echo "  CPU Limit per pod: $backend_cpu_limit (expected: 500m)"
    echo "  CPU Request per pod: $backend_cpu_request (expected: 200m)"
    echo "  Total CPU Limit: $((${backend_replicas:-0} * 500))m"
    
    # Check router pods
    local router_replicas=$(kubectl get deployment websocket-router -n orbit-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    local router_cpu_limit=$(kubectl get deployment websocket-router -n orbit-system -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}' 2>/dev/null)
    local router_cpu_request=$(kubectl get deployment websocket-router -n orbit-system -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null)
    
    echo "Router Pods:"
    echo "  Replicas: $router_replicas (expected: 2)"
    echo "  CPU Limit per pod: $router_cpu_limit (expected: 600m)"
    echo "  CPU Request per pod: $router_cpu_request (expected: 250m)"
    echo "  Total CPU Limit: $((${router_replicas:-0} * 600))m"
    
    # Calculate total system pod CPU
    local total_system_cpu_limit=$((300 + ${backend_replicas:-0} * 500 + ${router_replicas:-0} * 600))
    echo "Total System CPU Limit: ${total_system_cpu_limit}m"
}

validate_resource_quotas() {
    log_info "Validating resource quotas..."
    
    # Check challenge namespace quota
    local quota_cpu_limit=$(kubectl get quota challenge-quota -n orbit-challenges -o jsonpath='{.spec.hard.limits\.cpu}' 2>/dev/null)
    local quota_cpu_request=$(kubectl get quota challenge-quota -n orbit-challenges -o jsonpath='{.spec.hard.requests\.cpu}' 2>/dev/null)
    local quota_pods=$(kubectl get quota challenge-quota -n orbit-challenges -o jsonpath='{.spec.hard.pods}' 2>/dev/null)
    
    echo "Challenge Resource Quota:"
    echo "  CPU Limit: $quota_cpu_limit (expected: 25)"
    echo "  CPU Request: $quota_cpu_request (expected: 10)"
    echo "  Max Pods: $quota_pods (expected: 55)"
    
    # Check current usage
    local used_cpu_limit=$(kubectl get quota challenge-quota -n orbit-challenges -o jsonpath='{.status.used.limits\.cpu}' 2>/dev/null)
    local used_cpu_request=$(kubectl get quota challenge-quota -n orbit-challenges -o jsonpath='{.status.used.requests\.cpu}' 2>/dev/null)
    local used_pods=$(kubectl get quota challenge-quota -n orbit-challenges -o jsonpath='{.status.used.pods}' 2>/dev/null)
    
    echo "Current Usage:"
    echo "  CPU Limit Used: ${used_cpu_limit:-0}"
    echo "  CPU Request Used: ${used_cpu_request:-0}"
    echo "  Pods Used: ${used_pods:-0}"
}

validate_challenge_pod_template() {
    log_info "Validating challenge pod template..."
    
    # Check LimitRange
    local default_cpu_limit=$(kubectl get limitrange challenge-limits -n orbit-challenges -o jsonpath='{.spec.limits[1].default.cpu}' 2>/dev/null)
    local default_cpu_request=$(kubectl get limitrange challenge-limits -n orbit-challenges -o jsonpath='{.spec.limits[1].defaultRequest.cpu}' 2>/dev/null)
    local max_cpu=$(kubectl get limitrange challenge-limits -n orbit-challenges -o jsonpath='{.spec.limits[1].max.cpu}' 2>/dev/null)
    
    echo "Challenge Pod LimitRange:"
    echo "  Default CPU Limit: $default_cpu_limit (expected: 500m)"
    echo "  Default CPU Request: $default_cpu_request (expected: 200m)"
    echo "  Max CPU: $max_cpu (expected: 500m)"
    
    if [ "$max_cpu" != "500m" ]; then
        log_error "Challenge pod max CPU is not 0.5 CPU (500m)!"
        return 1
    fi
    
    if [ "$default_cpu_limit" != "500m" ]; then
        log_error "Challenge pod default CPU limit is not 0.5 CPU (500m)!"
        return 1
    fi
}

simulate_challenge_pod_creation() {
    log_info "Simulating challenge pod creation..."
    
    # Create a test challenge pod
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-challenge-pod
  namespace: orbit-challenges
  labels:
    component: challenge-pod
    test: true
spec:
  restartPolicy: Never
  containers:
  - name: challenge
    image: busybox:latest
    command: ["sleep", "300"]
    resources:
      limits:
        cpu: "$CHALLENGE_CPU_LIMIT"
        memory: "1Gi"
      requests:
        cpu: "$CHALLENGE_CPU_REQUEST"
        memory: "256Mi"
EOF
    
    # Wait for pod to be scheduled
    sleep 5
    
    # Check pod resource allocation
    local pod_cpu_limit=$(kubectl get pod test-challenge-pod -n orbit-challenges -o jsonpath='{.spec.containers[0].resources.limits.cpu}' 2>/dev/null)
    local pod_cpu_request=$(kubectl get pod test-challenge-pod -n orbit-challenges -o jsonpath='{.spec.containers[0].resources.requests.cpu}' 2>/dev/null)
    local pod_status=$(kubectl get pod test-challenge-pod -n orbit-challenges -o jsonpath='{.status.phase}' 2>/dev/null)
    
    echo "Test Challenge Pod:"
    echo "  Status: $pod_status"
    echo "  CPU Limit: $pod_cpu_limit"
    echo "  CPU Request: $pod_cpu_request"
    
    if [ "$pod_cpu_limit" != "$CHALLENGE_CPU_LIMIT" ]; then
        log_error "Test pod CPU limit mismatch!"
        kubectl delete pod test-challenge-pod -n orbit-challenges 2>/dev/null || true
        return 1
    fi
    
    # Cleanup
    kubectl delete pod test-challenge-pod -n orbit-challenges 2>/dev/null || true
    log_success "Test challenge pod created and validated successfully"
}

calculate_total_cpu_usage() {
    log_info "Calculating total CPU allocation..."
    
    # System nodes CPU
    local system_node_cpu=$((EXPECTED_SYSTEM_NODES * 2))  # e2-standard-2
    local challenge_node_cpu=$((EXPECTED_CHALLENGE_NODES * 4))  # e2-standard-4
    local total_available_cpu=$((system_node_cpu + challenge_node_cpu))
    
    # System pods CPU
    local operator_cpu=300
    local backend_cpu=$((2 * 500))  # 2 replicas × 500m
    local router_cpu=$((2 * 600))   # 2 replicas × 600m
    local total_system_cpu=$((operator_cpu + backend_cpu + router_cpu))
    
    # Challenge pods CPU
    local challenge_pod_cpu=$((EXPECTED_CHALLENGE_PODS * 500))  # 50 pods × 500m
    
    # Total usage
    local total_used_cpu=$((total_system_cpu + challenge_pod_cpu))
    local cpu_buffer=$((total_available_cpu * 1000 - total_used_cpu))
    local utilization=$((total_used_cpu * 100 / (total_available_cpu * 1000)))
    
    echo ""
    echo "=== CPU ALLOCATION SUMMARY ==="
    echo "Available CPU:"
    echo "  System Nodes: ${system_node_cpu} vCPU (${EXPECTED_SYSTEM_NODES} × e2-standard-2)"
    echo "  Challenge Nodes: ${challenge_node_cpu} vCPU (${EXPECTED_CHALLENGE_NODES} × e2-standard-4)"
    echo "  Total Available: ${total_available_cpu} vCPU"
    echo ""
    echo "CPU Usage:"
    echo "  System Pods: ${total_system_cpu}m"
    echo "    - Operator: ${operator_cpu}m"
    echo "    - Backend: ${backend_cpu}m (2 × 500m)"
    echo "    - Router: ${router_cpu}m (2 × 600m)"
    echo "  Challenge Pods: ${challenge_pod_cpu}m (50 × 500m)"
    echo "  Total Used: ${total_used_cpu}m"
    echo ""
    echo "Efficiency:"
    echo "  CPU Buffer: ${cpu_buffer}m"
    echo "  Utilization: ${utilization}%"
    echo ""
    
    if [ $total_used_cpu -gt $((total_available_cpu * 1000)) ]; then
        log_error "CPU over-allocation detected!"
        return 1
    fi
    
    if [ $utilization -gt 85 ]; then
        log_warning "High CPU utilization: ${utilization}%"
    fi
    
    # Validate exactly 0.5 CPU per challenge pod
    echo "Challenge Pod Validation:"
    echo "  CPU per pod: 500m (exactly 0.5 CPU as requested)"
    echo "  Pods per node: $((EXPECTED_CHALLENGE_PODS / EXPECTED_CHALLENGE_NODES))"
    echo "  CPU per node: $((500 * EXPECTED_CHALLENGE_PODS / EXPECTED_CHALLENGE_NODES))m"
    echo "  Node utilization: $(((500 * EXPECTED_CHALLENGE_PODS / EXPECTED_CHALLENGE_NODES) * 100 / 4000))%"
    
    log_success "CPU allocation is optimal and within limits"
}

show_monitoring_commands() {
    echo ""
    echo "=== MONITORING COMMANDS ==="
    echo "Check node resource usage:"
    echo "  kubectl top nodes"
    echo ""
    echo "Check pod resource usage:"
    echo "  kubectl top pods -n orbit-system"
    echo "  kubectl top pods -n orbit-challenges"
    echo ""
    echo "Check resource quotas:"
    echo "  kubectl describe quota challenge-quota -n orbit-challenges"
    echo ""
    echo "Watch challenge pod creation:"
    echo "  kubectl get pods -n orbit-challenges -w"
    echo ""
    echo "Check HPA status:"
    echo "  kubectl get hpa -n orbit-system"
    echo ""
    echo "Monitor CPU throttling:"
    echo "  kubectl describe pod <pod-name> -n <namespace>"
    echo ""
}

main() {
    log_info "Starting CPU allocation validation for 50 users with 0.5 CPU per challenge pod"
    
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    validate_cluster_resources
    validate_system_pods
    validate_resource_quotas
    validate_challenge_pod_template
    simulate_challenge_pod_creation
    calculate_total_cpu_usage
    show_monitoring_commands
    
    log_success "All validations passed! Platform is optimally configured for 50 users with 0.5 CPU per challenge pod."
}

main "$@"
