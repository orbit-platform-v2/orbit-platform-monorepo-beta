#!/bin/bash

# Orbit Challenge Platform - Optimized Deployment Script
# Optimized for 50 concurrent users with 50 CPU limit on GCP

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Resource constraints
MAX_CPU_LIMIT=50
TARGET_CHALLENGE_PODS=50
CHALLENGE_NODES=10
SYSTEM_NODES=2

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

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Orbit Challenge Platform with Resource Optimization

OPTIONS:
    -p, --project-id     GCP Project ID (required)
    -r, --region         GCP Region [default: us-central1]
    -c, --cluster-name   GKE Cluster name [default: orbit-challenge-cluster]
    --validate-only      Only validate resource allocation
    --dry-run           Show what would be deployed
    -h, --help          Show this help message

RESOURCE CONFIGURATION:
    - Target: 50 concurrent challenge pods
    - CPU Limit: 50 vCPU total
    - Node Distribution: 2 system + 10 challenge nodes
    - Challenge Pod Density: 5 pods per challenge node

EOF
}

validate_resource_allocation() {
    log_info "Validating resource allocation..."
    
    # Calculate total CPU requirements
    local system_cpu=$((SYSTEM_NODES * 2))  # e2-standard-2 = 2 vCPU
    local challenge_cpu=$((CHALLENGE_NODES * 4))  # e2-standard-4 = 4 vCPU
    local total_cpu=$((system_cpu + challenge_cpu))
    
    log_info "Resource Calculation:"
    log_info "  System Nodes: $SYSTEM_NODES × 2 vCPU = $system_cpu vCPU"
    log_info "  Challenge Nodes: $CHALLENGE_NODES × 4 vCPU = $challenge_cpu vCPU"
    log_info "  Total Required: $total_cpu vCPU"
    log_info "  GCP Limit: $MAX_CPU_LIMIT vCPU"
    log_info "  Buffer: $((MAX_CPU_LIMIT - total_cpu)) vCPU"
    
    if [ $total_cpu -gt $MAX_CPU_LIMIT ]; then
        log_error "Resource allocation exceeds CPU limit!"
        log_error "Required: $total_cpu vCPU, Available: $MAX_CPU_LIMIT vCPU"
        exit 1
    fi
    
    # Calculate challenge pod distribution
    local pods_per_node=$((TARGET_CHALLENGE_PODS / CHALLENGE_NODES))
    local cpu_per_pod=500  # 500m CPU per pod
    local cpu_per_node=$((pods_per_node * cpu_per_pod))
    local cpu_utilization=$((cpu_per_node * 100 / 4000))  # 4000m = 4 vCPU
    
    log_info "Challenge Pod Distribution:"
    log_info "  Total Pods: $TARGET_CHALLENGE_PODS"
    log_info "  Pods per Node: $pods_per_node"
    log_info "  CPU per Pod: ${cpu_per_pod}m"
    log_info "  CPU per Node: ${cpu_per_node}m (${cpu_utilization}% utilization)"
    
    if [ $cpu_utilization -gt 75 ]; then
        log_warning "High CPU utilization per challenge node: ${cpu_utilization}%"
        log_warning "Consider reducing pods per node or CPU per pod"
    fi
    
    log_success "Resource allocation validation passed"
}

check_cluster_status() {
    log_info "Checking cluster status..."
    
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        log_error "Make sure cluster is created and kubectl is configured"
        exit 1
    fi
    
    # Check node pools
    local system_nodes=$(kubectl get nodes -l role=system --no-headers 2>/dev/null | wc -l)
    local challenge_nodes=$(kubectl get nodes -l role=challenge --no-headers 2>/dev/null | wc -l)
    
    log_info "Current cluster state:"
    log_info "  System nodes: $system_nodes (expected: $SYSTEM_NODES)"
    log_info "  Challenge nodes: $challenge_nodes (expected: $CHALLENGE_NODES)"
    
    if [ $system_nodes -lt $SYSTEM_NODES ]; then
        log_warning "Insufficient system nodes. Expected: $SYSTEM_NODES, Found: $system_nodes"
    fi
    
    if [ $challenge_nodes -lt $CHALLENGE_NODES ]; then
        log_warning "Insufficient challenge nodes. Expected: $CHALLENGE_NODES, Found: $challenge_nodes"
    fi
}

deploy_system_components() {
    log_info "Deploying system components..."
    
    # Create namespaces if they don't exist
    kubectl create namespace orbit-system --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace orbit-challenges --dry-run=client -o yaml | kubectl apply -f -
    
    # Label namespaces
    kubectl label namespace orbit-system name=orbit-system --overwrite
    kubectl label namespace orbit-challenges name=orbit-challenges --overwrite
    
    # Deploy resource quotas and limits
    log_info "Applying resource quotas and limits..."
    kubectl apply -f "$PROJECT_ROOT/k8s-manifests/base/challenge-resources.yaml"
    
    # Deploy system pods with resource constraints
    log_info "Deploying Orbit Operator..."
    envsubst < "$PROJECT_ROOT/k8s-manifests/base/operator.yaml" | kubectl apply -f -
    
    log_info "Deploying Backend API..."
    envsubst < "$PROJECT_ROOT/k8s-manifests/base/backend.yaml" | kubectl apply -f -
    
    log_info "Deploying WebSocket Router..."
    envsubst < "$PROJECT_ROOT/k8s-manifests/base/websocket-router.yaml" | kubectl apply -f -
    
    log_success "System components deployed"
}

wait_for_deployments() {
    log_info "Waiting for deployments to be ready..."
    
    # Wait for system deployments
    kubectl wait --for=condition=available --timeout=300s deployment/orbit-operator -n orbit-system
    kubectl wait --for=condition=available --timeout=300s deployment/orbit-backend -n orbit-system
    kubectl wait --for=condition=available --timeout=300s deployment/websocket-router -n orbit-system
    
    log_success "All deployments are ready"
}

verify_resource_usage() {
    log_info "Verifying actual resource usage..."
    
    # Get resource usage from metrics server (if available)
    if kubectl top nodes &>/dev/null; then
        log_info "Node resource usage:"
        kubectl top nodes
        
        log_info "Pod resource usage in orbit-system:"
        kubectl top pods -n orbit-system
    else
        log_warning "Metrics server not available, cannot show resource usage"
    fi
    
    # Check resource quotas
    log_info "Resource quota status:"
    kubectl describe quota challenge-quota -n orbit-challenges
}

create_sample_challenge() {
    log_info "Creating sample challenge for testing..."
    
    cat << EOF | kubectl apply -f -
apiVersion: challenges.orbit.io/v1
kind: Challenge
metadata:
  name: docker-basics
  namespace: orbit-challenges
spec:
  name: "Docker Basics"
  description: "Learn Docker fundamentals"
  image: "ubuntu:20.04"
  difficulty: "beginner"
  maxSessions: 10
  ttlSecondsAfterCreation: 1800
  resources:
    cpu: "500m"
    memory: "1Gi"
    storage: "5Gi"
  environment:
    - name: CHALLENGE_TYPE
      value: "docker-basics"
  instructions: |
    Welcome to Docker Basics Challenge!
    
    In this challenge you will:
    1. Learn basic Docker commands
    2. Create your first Dockerfile
    3. Build and run containers
    
    Use the terminal to complete the tasks.
  hints:
    - "Use 'docker --help' to see available commands"
    - "Start with 'docker version' to check your setup"
  tags:
    - "docker"
    - "containers"
    - "beginner"
EOF
    
    log_success "Sample challenge created"
}

show_deployment_summary() {
    log_success "Deployment completed successfully!"
    
    cat << EOF

🎉 Orbit Challenge Platform is ready!

📊 Resource Summary:
   • Total CPU: $((SYSTEM_NODES * 2 + CHALLENGE_NODES * 4)) vCPU allocated
   • CPU Buffer: $((MAX_CPU_LIMIT - SYSTEM_NODES * 2 - CHALLENGE_NODES * 4)) vCPU remaining
   • Challenge Capacity: $TARGET_CHALLENGE_PODS concurrent pods
   • Pod Distribution: $((TARGET_CHALLENGE_PODS / CHALLENGE_NODES)) pods per challenge node

🔗 Service Endpoints:
   • Backend API: http://$(kubectl get svc orbit-backend -n orbit-system -o jsonpath='{.spec.clusterIP}'):8000
   • WebSocket Router: ws://$(kubectl get svc websocket-router -n orbit-system -o jsonpath='{.spec.clusterIP}'):8080
   • Metrics: http://$(kubectl get svc websocket-router -n orbit-system -o jsonpath='{.spec.clusterIP}'):9090

🎯 Next Steps:
   1. Set up ingress for external access
   2. Deploy your challenge container images
   3. Create additional Challenge CRDs
   4. Configure monitoring dashboards
   5. Set up backup procedures

📋 Useful Commands:
   • Check system pods: kubectl get pods -n orbit-system
   • Check challenge quota: kubectl describe quota challenge-quota -n orbit-challenges
   • Monitor resource usage: kubectl top nodes && kubectl top pods --all-namespaces
   • View challenges: kubectl get challenges -n orbit-challenges
   • Create session: kubectl apply -f session.yaml

📈 Monitoring:
   • Prometheus: kubectl port-forward -n orbit-monitoring svc/prometheus-operated 9090:9090
   • Grafana: kubectl port-forward -n orbit-monitoring svc/prometheus-grafana 3000:80

EOF
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -c|--cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --validate-only)
                validate_resource_allocation
                exit 0
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Set defaults
    REGION="${REGION:-us-central1}"
    CLUSTER_NAME="${CLUSTER_NAME:-orbit-challenge-cluster}"
    
    # Validate inputs
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use --project-id option."
        usage
        exit 1
    fi
    
    # Set environment variables for envsubst
    export PROJECT_ID REGION CLUSTER_NAME
    
    log_info "Starting optimized deployment for $TARGET_CHALLENGE_PODS concurrent users"
    log_info "Project: $PROJECT_ID, Region: $REGION, Cluster: $CLUSTER_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No changes will be made"
        validate_resource_allocation
        exit 0
    fi
    
    validate_resource_allocation
    check_cluster_status
    deploy_system_components
    wait_for_deployments
    verify_resource_usage
    create_sample_challenge
    show_deployment_summary
}

# Run main function
main "$@"
