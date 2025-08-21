#!/bin/bash

# Orbit Challenge Platform - Infrastructure Pause Script
# Pauses the infrastructure to save costs when not in use

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
SAVE_STATE=true
FORCE=false

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

Pause Orbit Challenge Platform Infrastructure to Save Costs

OPTIONS:
    -p, --project-id     GCP Project ID (required)
    -r, --region         GCP Region [default: us-central1]
    -c, --cluster-name   GKE Cluster name [default: orbit-challenge-cluster]
    -s, --save-state     Save current state before pause [default: true]
    -f, --force          Force pause without confirmation [default: false]
    -h, --help           Show this help message

EXAMPLES:
    $0 --project-id my-gcp-project
    $0 --project-id my-gcp-project --region europe-west1 --force

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
        -s|--save-state)
            SAVE_STATE=true
            shift
            ;;
        --no-save-state)
            SAVE_STATE=false
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

# Confirmation prompt
if [[ "$FORCE" != "true" ]]; then
    echo
    log_warning "⚠️  INFRASTRUCTURE PAUSE CONFIRMATION ⚠️"
    echo
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Cluster: $CLUSTER_NAME"
    echo "Save State: $SAVE_STATE"
    echo
    echo "This will:"
    echo "1. Scale down all non-essential workloads"
    echo "2. Resize node pools to minimum (1 node per pool)"
    echo "3. Save current deployment state (if enabled)"
    echo "4. Significantly reduce your GCP costs"
    echo
    read -p "Are you sure you want to pause the infrastructure? (yes/no): " confirm
    
    if [[ $confirm != "yes" ]]; then
        log_info "Operation cancelled"
        exit 0
    fi
fi

log_info "Starting infrastructure pause process..."

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

# Create pause state directory
PAUSE_STATE_DIR="./pause-state/$(date +%Y%m%d-%H%M%S)"
if [[ "$SAVE_STATE" == "true" ]]; then
    log_info "Creating state backup directory: $PAUSE_STATE_DIR"
    mkdir -p "$PAUSE_STATE_DIR"
fi

# Function to save deployment state
save_deployment_state() {
    local namespace=$1
    local deployment=$2
    
    if [[ "$SAVE_STATE" == "true" ]]; then
        log_info "Saving state for deployment $deployment in namespace $namespace"
        kubectl get deployment "$deployment" -n "$namespace" -o yaml > "$PAUSE_STATE_DIR/${namespace}-${deployment}.yaml"
        
        # Save replica count
        local replicas=$(kubectl get deployment "$deployment" -n "$namespace" -o jsonpath='{.spec.replicas}')
        echo "$replicas" > "$PAUSE_STATE_DIR/${namespace}-${deployment}.replicas"
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

# 1. Save and scale down system deployments
log_info "📦 Scaling down system deployments..."

# Backend - scale to 1 replica (keep minimal functionality)
save_deployment_state "orbit-system" "orbit-backend"
scale_deployment "orbit-system" "orbit-backend" 1

# WebSocket Router - scale to 1 replica
save_deployment_state "orbit-system" "websocket-router"
scale_deployment "orbit-system" "websocket-router" 1

# Operator - keep running (essential for cluster management)
log_info "Keeping operator running (essential service)"

# 2. Save and terminate all challenge pods
log_info "🎯 Terminating all challenge pods..."
if kubectl get namespace orbit-challenges &>/dev/null; then
    # Save list of active challenge pods
    if [[ "$SAVE_STATE" == "true" ]]; then
        kubectl get pods -n orbit-challenges -o yaml > "$PAUSE_STATE_DIR/challenge-pods.yaml"
        kubectl get pods -n orbit-challenges --no-headers | wc -l > "$PAUSE_STATE_DIR/challenge-pods.count"
    fi
    
    # Delete all challenge pods
    kubectl delete pods --all -n orbit-challenges --grace-period=30
    log_success "All challenge pods terminated"
else
    log_warning "Challenge namespace not found"
fi

# 3. Scale down monitoring (if exists)
log_info "📊 Scaling down monitoring components..."
if kubectl get namespace monitoring &>/dev/null; then
    # Prometheus
    if kubectl get deployment prometheus-server -n monitoring &>/dev/null; then
        save_deployment_state "monitoring" "prometheus-server"
        scale_deployment "monitoring" "prometheus-server" 0
    fi
    
    # Grafana
    if kubectl get deployment grafana -n monitoring &>/dev/null; then
        save_deployment_state "monitoring" "grafana"
        scale_deployment "monitoring" "grafana" 0
    fi
fi

# 4. Wait for pods to terminate
log_info "⏳ Waiting for pods to terminate..."
sleep 30

# 5. Resize node pools to minimum
log_info "🔽 Resizing node pools to minimum..."

# System node pool - minimum 1 node
log_info "Resizing system node pool to 1 node..."
gcloud container clusters resize "$CLUSTER_NAME" \
    --node-pool="system-pool" \
    --num-nodes=1 \
    --region="$REGION" \
    --quiet

# Challenge node pools - minimum 1 node each (total: 1 node for all challenges)
log_info "Resizing challenge node pools to minimal configuration..."
for i in {1..10}; do
    gcloud container clusters resize "$CLUSTER_NAME" \
        --node-pool="challenge-pool-$i" \
        --num-nodes=1 \
        --region="$REGION" \
        --quiet
done

# 6. Enable cluster autoscaling to scale to zero if possible
log_info "🔧 Configuring autoscaling for cost optimization..."
gcloud container clusters update "$CLUSTER_NAME" \
    --region="$REGION" \
    --enable-autoscaling \
    --min-nodes=0 \
    --max-nodes=1 \
    --node-pool="system-pool"

for i in {1..10}; do
    gcloud container clusters update "$CLUSTER_NAME" \
        --region="$REGION" \
        --enable-autoscaling \
        --min-nodes=0 \
        --max-nodes=1 \
        --node-pool="challenge-pool-$i"
done

# 7. Apply resource quotas to prevent accidental scaling
log_info "🚫 Applying strict resource quotas..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: pause-mode-quota
  namespace: orbit-challenges
spec:
  hard:
    pods: "5"
    requests.cpu: "2500m"
    requests.memory: "5Gi"
    limits.cpu: "2500m"
    limits.memory: "5Gi"
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: pause-mode-quota
  namespace: orbit-system
spec:
  hard:
    pods: "10"
    requests.cpu: "2000m"
    requests.memory: "4Gi"
    limits.cpu: "2000m"
    limits.memory: "4Gi"
EOF

# 8. Save pause metadata
if [[ "$SAVE_STATE" == "true" ]]; then
    log_info "💾 Saving pause metadata..."
    cat > "$PAUSE_STATE_DIR/pause-metadata.json" <<EOF
{
  "pause_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project_id": "$PROJECT_ID",
  "region": "$REGION",
  "cluster_name": "$CLUSTER_NAME",
  "original_node_counts": {
    "system_pool": 2,
    "challenge_pools": 10
  },
  "paused_by": "$(whoami)",
  "pause_reason": "Cost optimization"
}
EOF
    
    log_success "State saved to: $PAUSE_STATE_DIR"
fi

# 9. Calculate cost savings
log_info "💰 Calculating estimated cost savings..."
echo
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    INFRASTRUCTURE PAUSED                     ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║ Cluster: $CLUSTER_NAME"
echo "║ Region: $REGION"
echo "║ Pause Time: $(date)"
echo "║"
echo "║ COST SAVINGS ESTIMATE (per hour):"
echo "║ • System Nodes: 1/2 nodes running (~50% savings)"
echo "║ • Challenge Nodes: 10/10 nodes at minimum (~80% savings)"
echo "║ • Application Pods: ~90% reduction"
echo "║ • Estimated Total Savings: ~70-80% of running costs"
echo "║"
echo "║ MAINTAINED SERVICES:"
echo "║ • 1x Backend replica (minimal API access)"
echo "║ • 1x Router replica (basic functionality)"
echo "║ • 1x Operator (cluster management)"
echo "║"
echo "║ TO RESUME: ./scripts/resume-infrastructure.sh"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

log_success "✅ Infrastructure successfully paused!"
log_info "💡 To resume full operations, run: ./scripts/resume-infrastructure.sh --project-id $PROJECT_ID"

if [[ "$SAVE_STATE" == "true" ]]; then
    log_info "📂 State backup location: $PAUSE_STATE_DIR"
fi

exit 0
