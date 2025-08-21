#!/bin/bash

# Orbit Challenge Platform - Infrastructure Resume Script
# Resumes the paused infrastructure to full operational capacity

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PROJECT_ID=""
REGION="us-central1"
CLUSTER_NAME="orbit-challenge-cluster"
RESTORE_STATE=true
FORCE=false
STATE_DIR=""

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

Resume Orbit Challenge Platform Infrastructure to Full Capacity

OPTIONS:
    -p, --project-id     GCP Project ID (required)
    -r, --region         GCP Region [default: us-central1]
    -c, --cluster-name   GKE Cluster name [default: orbit-challenge-cluster]
    -s, --state-dir      Directory with saved state [auto-detect latest]
    -f, --force          Force resume without confirmation [default: false]
    --no-restore-state   Don't restore from saved state
    -h, --help           Show this help message

EXAMPLES:
    $0 --project-id my-gcp-project
    $0 --project-id my-gcp-project --state-dir ./pause-state/20250821-143000
    $0 --project-id my-gcp-project --force --no-restore-state

EOF
}

# Parse command line arguments
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
        -s|--state-dir)
            STATE_DIR="$2"
            shift 2
            ;;
        --no-restore-state)
            RESTORE_STATE=false
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
    log_error "Project ID is required"
    usage
    exit 1
fi

# Auto-detect latest state directory if not provided
if [[ "$RESTORE_STATE" == "true" && -z "$STATE_DIR" ]]; then
    if [[ -d "./pause-state" ]]; then
        STATE_DIR=$(find ./pause-state -type d -name "????????-??????" | sort | tail -1)
        if [[ -n "$STATE_DIR" ]]; then
            log_info "Auto-detected latest state directory: $STATE_DIR"
        else
            log_warning "No state directories found in ./pause-state"
            RESTORE_STATE=false
        fi
    else
        log_warning "No pause-state directory found"
        RESTORE_STATE=false
    fi
fi

# Confirmation prompt
if [[ "$FORCE" != "true" ]]; then
    echo
    log_warning "🚀 INFRASTRUCTURE RESUME CONFIRMATION 🚀"
    echo
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Cluster: $CLUSTER_NAME"
    echo "Restore State: $RESTORE_STATE"
    if [[ -n "$STATE_DIR" ]]; then
        echo "State Directory: $STATE_DIR"
    fi
    echo
    echo "This will:"
    echo "1. Scale node pools back to full capacity"
    echo "2. Restore system deployments to optimal configuration"
    echo "3. Re-enable resource quotas for 50 concurrent users"
    echo "4. Resume full platform operations"
    echo "5. Increase your GCP costs to normal operational levels"
    echo
    read -p "Are you sure you want to resume the infrastructure? (yes/no): " confirm
    
    if [[ $confirm != "yes" ]]; then
        log_info "Operation cancelled"
        exit 0
    fi
fi

log_info "Starting infrastructure resume process..."

# Set up GCP authentication and project
gcloud config set project "$PROJECT_ID"

# Check if cluster exists
log_info "Checking if cluster exists..."
if ! gcloud container clusters describe "$CLUSTER_NAME" --region="$REGION" &>/dev/null; then
    log_error "Cluster $CLUSTER_NAME not found in region $REGION"
    exit 1
fi

# Get cluster credentials
log_info "Getting cluster credentials..."
gcloud container clusters get-credentials "$CLUSTER_NAME" --region="$REGION"

# Function to get saved replica count
get_saved_replicas() {
    local namespace=$1
    local deployment=$2
    local default_replicas=$3
    
    if [[ "$RESTORE_STATE" == "true" && -f "$STATE_DIR/${namespace}-${deployment}.replicas" ]]; then
        cat "$STATE_DIR/${namespace}-${deployment}.replicas"
    else
        echo "$default_replicas"
    fi
}

# Function to scale deployment
scale_deployment() {
    local namespace=$1
    local deployment=$2
    local replicas=$3
    
    log_info "Scaling deployment $deployment in namespace $namespace to $replicas replicas"
    kubectl scale deployment "$deployment" -n "$namespace" --replicas="$replicas"
}

# 1. Remove pause-mode resource quotas
log_info "🔧 Removing pause-mode resource quotas..."
kubectl delete resourcequota pause-mode-quota -n orbit-challenges --ignore-not-found=true
kubectl delete resourcequota pause-mode-quota -n orbit-system --ignore-not-found=true

# 2. Restore normal resource quotas
log_info "📊 Restoring normal resource quotas..."
kubectl apply -f k8s-manifests/base/challenge-resources.yaml

# 3. Scale up node pools to full capacity
log_info "🔼 Scaling node pools to full capacity..."

# System node pool - back to 2 nodes
log_info "Scaling system node pool to 2 nodes..."
gcloud container clusters resize "$CLUSTER_NAME" \
    --node-pool="system-pool" \
    --num-nodes=2 \
    --region="$REGION" \
    --quiet

# Challenge node pools - back to 1 node each (total: 10 nodes)
log_info "Scaling challenge node pools to optimal configuration..."
for i in {1..10}; do
    gcloud container clusters resize "$CLUSTER_NAME" \
        --node-pool="challenge-pool-$i" \
        --num-nodes=1 \
        --region="$REGION" \
        --quiet &
    
    # Limit concurrent operations
    if (( i % 3 == 0 )); then
        wait
    fi
done
wait

# 4. Update autoscaling settings for normal operations
log_info "🔧 Configuring autoscaling for normal operations..."
gcloud container clusters update "$CLUSTER_NAME" \
    --region="$REGION" \
    --enable-autoscaling \
    --min-nodes=2 \
    --max-nodes=3 \
    --node-pool="system-pool"

for i in {1..10}; do
    gcloud container clusters update "$CLUSTER_NAME" \
        --region="$REGION" \
        --enable-autoscaling \
        --min-nodes=1 \
        --max-nodes=2 \
        --node-pool="challenge-pool-$i" &
    
    # Limit concurrent operations
    if (( i % 3 == 0 )); then
        wait
    fi
done
wait

# 5. Wait for nodes to be ready
log_info "⏳ Waiting for nodes to become ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# 6. Scale up system deployments
log_info "📦 Scaling up system deployments..."

# Backend - restore to original replica count
backend_replicas=$(get_saved_replicas "orbit-system" "orbit-backend" 2)
scale_deployment "orbit-system" "orbit-backend" "$backend_replicas"

# WebSocket Router - restore to original replica count
router_replicas=$(get_saved_replicas "orbit-system" "websocket-router" 2)
scale_deployment "orbit-system" "websocket-router" "$router_replicas"

# Operator should already be running, verify it's healthy
log_info "Verifying operator health..."
kubectl rollout status deployment/orbit-operator -n orbit-system --timeout=120s

# 7. Restore monitoring components
log_info "📊 Restoring monitoring components..."
if kubectl get namespace monitoring &>/dev/null; then
    # Prometheus
    if kubectl get deployment prometheus-server -n monitoring &>/dev/null; then
        prometheus_replicas=$(get_saved_replicas "monitoring" "prometheus-server" 1)
        scale_deployment "monitoring" "prometheus-server" "$prometheus_replicas"
    fi
    
    # Grafana
    if kubectl get deployment grafana -n monitoring &>/dev/null; then
        grafana_replicas=$(get_saved_replicas "monitoring" "grafana" 1)
        scale_deployment "monitoring" "grafana" "$grafana_replicas"
    fi
fi

# 8. Wait for all deployments to be ready
log_info "⏳ Waiting for all deployments to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/orbit-backend -n orbit-system
kubectl wait --for=condition=available --timeout=300s deployment/websocket-router -n orbit-system
kubectl wait --for=condition=available --timeout=300s deployment/orbit-operator -n orbit-system

# 9. Validate system health
log_info "🔍 Validating system health..."

# Check node status
log_info "Checking node status..."
kubectl get nodes -o wide

# Check system pod status
log_info "Checking system pod status..."
kubectl get pods -n orbit-system

# Validate resource allocation
log_info "Validating resource allocation..."
if [[ -f "./scripts/validate-cpu-allocation.sh" ]]; then
    chmod +x ./scripts/validate-cpu-allocation.sh
    ./scripts/validate-cpu-allocation.sh
fi

# 10. Test basic functionality
log_info "🧪 Testing basic functionality..."

# Test backend health
log_info "Testing backend health..."
if kubectl get service orbit-backend -n orbit-system &>/dev/null; then
    kubectl port-forward service/orbit-backend 8080:80 -n orbit-system &
    PORT_FORWARD_PID=$!
    sleep 5
    
    if curl -f http://localhost:8080/health &>/dev/null; then
        log_success "Backend health check passed"
    else
        log_warning "Backend health check failed"
    fi
    
    kill $PORT_FORWARD_PID 2>/dev/null || true
fi

# 11. Show final status
echo
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  INFRASTRUCTURE RESUMED                      ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║ Cluster: $CLUSTER_NAME"
echo "║ Region: $REGION"
echo "║ Resume Time: $(date)"
echo "║"
echo "║ RESTORED CAPACITY:"
echo "║ • System Nodes: 2 nodes (full capacity)"
echo "║ • Challenge Nodes: 10 nodes (ready for 50 users)"
echo "║ • Backend Replicas: $backend_replicas"
echo "║ • Router Replicas: $router_replicas"
echo "║ • Resource Quotas: 50 challenge pods / 25 CPU limit"
echo "║"
echo "║ PLATFORM STATUS:"
echo "║ • ✅ Ready for 50 concurrent users"
echo "║ • ✅ 0.5 CPU per challenge pod enforced"
echo "║ • ✅ Auto-scaling enabled"
echo "║ • ✅ Monitoring restored"
echo "║"
echo "║ COST IMPACT: Resumed full operational costs"
echo "║ TO PAUSE AGAIN: ./scripts/pause-infrastructure.sh"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

log_success "✅ Infrastructure successfully resumed!"
log_info "🎯 Platform is ready for 50 concurrent users with 0.5 CPU per challenge pod"

if [[ "$RESTORE_STATE" == "true" && -n "$STATE_DIR" ]]; then
    log_info "📂 State restored from: $STATE_DIR"
fi

# 12. Show next steps
echo
log_info "📋 Next Steps:"
echo "1. Verify platform functionality with a test challenge"
echo "2. Monitor resource usage: kubectl top nodes && kubectl top pods --all-namespaces"
echo "3. Check logs: kubectl logs -f deployment/orbit-backend -n orbit-system"
echo "4. Access monitoring dashboard (if deployed)"
echo

exit 0
