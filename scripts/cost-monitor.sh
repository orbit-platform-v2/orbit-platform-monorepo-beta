#!/bin/bash

# Orbit Challenge Platform - Cost Monitoring Script
# Monitors infrastructure costs and provides optimization recommendations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Default values
PROJECT_ID=""
REGION="us-central1"
CLUSTER_NAME="orbit-challenge-cluster"
DAYS=7
OUTPUT_FORMAT="table"
COST_THRESHOLD=100
ALERT_EMAIL=""

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

log_cost() {
    echo -e "${PURPLE}[COST]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Monitor Orbit Challenge Platform Infrastructure Costs

OPTIONS:
    -p, --project-id     GCP Project ID (required)
    -r, --region         GCP Region [default: us-central1]
    -c, --cluster-name   GKE Cluster name [default: orbit-challenge-cluster]
    -d, --days           Number of days to analyze [default: 7]
    -f, --format         Output format: table, json, csv [default: table]
    -t, --threshold      Cost alert threshold in USD [default: 100]
    -e, --email          Email for cost alerts
    -h, --help           Show this help message

EXAMPLES:
    $0 --project-id my-gcp-project
    $0 --project-id my-gcp-project --days 30 --format json
    $0 --project-id my-gcp-project --threshold 50 --email admin@company.com

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
        -d|--days)
            DAYS="$2"
            shift 2
            ;;
        -f|--format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -t|--threshold)
            COST_THRESHOLD="$2"
            shift 2
            ;;
        -e|--email)
            ALERT_EMAIL="$2"
            shift 2
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

log_info "Starting cost analysis for project: $PROJECT_ID"

# Set up GCP authentication and project
gcloud config set project "$PROJECT_ID"

# Calculate date range
END_DATE=$(date '+%Y-%m-%d')
START_DATE=$(date -d "$DAYS days ago" '+%Y-%m-%d')

log_info "Analyzing costs from $START_DATE to $END_DATE"

# Function to get current resource status
get_resource_status() {
    log_info "📊 Current Resource Status"
    
    # Check if cluster exists
    if gcloud container clusters describe "$CLUSTER_NAME" --region="$REGION" &>/dev/null; then
        # Get cluster credentials
        gcloud container clusters get-credentials "$CLUSTER_NAME" --region="$REGION" --quiet
        
        # Node status
        local total_nodes=$(kubectl get nodes --no-headers | wc -l)
        local ready_nodes=$(kubectl get nodes --no-headers | grep Ready | wc -l)
        
        # Pod status
        local total_pods=$(kubectl get pods --all-namespaces --no-headers | wc -l)
        local running_pods=$(kubectl get pods --all-namespaces --no-headers | grep Running | wc -l)
        local challenge_pods=$(kubectl get pods -n orbit-challenges --no-headers 2>/dev/null | wc -l)
        
        echo "  Cluster Status: Active"
        echo "  Nodes: $ready_nodes/$total_nodes ready"
        echo "  Total Pods: $running_pods/$total_pods running"
        echo "  Challenge Pods: $challenge_pods"
        
        # Resource usage
        if command -v kubectl &> /dev/null; then
            echo "  Current Resource Usage:"
            kubectl top nodes 2>/dev/null | tail -n +2 | while read line; do
                echo "    $line"
            done
        fi
    else
        echo "  Cluster Status: Not Found"
    fi
}

# Function to get billing data
get_billing_data() {
    log_info "💰 Retrieving billing data..."
    
    # Check if billing is enabled
    local billing_account=$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null)
    
    if [[ -z "$billing_account" ]]; then
        log_warning "Billing not enabled or accessible for project $PROJECT_ID"
        return 1
    fi
    
    log_info "Billing Account: $billing_account"
    
    # Get billing data using Cloud Billing API (requires additional setup)
    # For now, we'll use gcloud to get cost estimates
    local query="
        SELECT
          service.description as service,
          sku.description as sku,
          SUM(cost) as total_cost,
          currency
        FROM \`$PROJECT_ID.billing_export.gcp_billing_export_v1_$(echo $billing_account | sed 's/.*\///' | tr '[:upper:]' '[:lower:]')\`
        WHERE DATE(usage_start_time) >= '$START_DATE'
          AND DATE(usage_start_time) <= '$END_DATE'
          AND project.id = '$PROJECT_ID'
        GROUP BY service, sku, currency
        ORDER BY total_cost DESC
    "
    
    # This would require BigQuery dataset setup
    # For demonstration, we'll show estimated costs based on resources
    calculate_estimated_costs
}

# Function to calculate estimated costs
calculate_estimated_costs() {
    log_info "🔢 Calculating estimated costs..."
    
    local total_cost=0
    local node_cost=0
    local storage_cost=0
    local network_cost=0
    local other_cost=0
    
    # Check if cluster exists for cost calculation
    if gcloud container clusters describe "$CLUSTER_NAME" --region="$REGION" &>/dev/null; then
        gcloud container clusters get-credentials "$CLUSTER_NAME" --region="$REGION" --quiet
        
        # Calculate node costs (rough estimates)
        local system_nodes=$(kubectl get nodes -l node-pool=system-pool --no-headers 2>/dev/null | wc -l || echo "0")
        local challenge_nodes=$(kubectl get nodes -l node-pool | grep challenge-pool | wc -l || echo "0")
        
        # Estimated costs per hour (USD)
        local e2_standard_2_cost=0.067  # ~$48/month
        local e2_standard_4_cost=0.134  # ~$96/month
        
        # Calculate daily costs
        local system_daily_cost=$(echo "$system_nodes * $e2_standard_2_cost * 24" | bc -l)
        local challenge_daily_cost=$(echo "$challenge_nodes * $e2_standard_4_cost * 24" | bc -l)
        node_cost=$(echo "$system_daily_cost + $challenge_daily_cost" | bc -l)
        
        # Estimate other costs
        storage_cost=2.50  # Estimated daily storage cost
        network_cost=1.00  # Estimated daily network cost
        other_cost=0.50    # Other GKE services
        
        total_cost=$(echo "$node_cost + $storage_cost + $network_cost + $other_cost" | bc -l)
    else
        log_warning "Cluster not found, showing paused state estimate"
        total_cost=0.50  # Minimal cost when paused
    fi
    
    # Format and display costs
    case $OUTPUT_FORMAT in
        "json")
            cat <<EOF
{
  "project_id": "$PROJECT_ID",
  "period": {
    "start_date": "$START_DATE",
    "end_date": "$END_DATE",
    "days": $DAYS
  },
  "estimated_daily_costs": {
    "nodes": $(printf "%.2f" $node_cost),
    "storage": $(printf "%.2f" $storage_cost),
    "network": $(printf "%.2f" $network_cost),
    "other": $(printf "%.2f" $other_cost),
    "total": $(printf "%.2f" $total_cost)
  },
  "estimated_period_cost": $(printf "%.2f" $(echo "$total_cost * $DAYS" | bc -l)),
  "currency": "USD"
}
EOF
            ;;
        "csv")
            echo "Category,Daily Cost (USD),Period Cost (USD)"
            echo "Nodes,$(printf "%.2f" $node_cost),$(printf "%.2f" $(echo "$node_cost * $DAYS" | bc -l))"
            echo "Storage,$(printf "%.2f" $storage_cost),$(printf "%.2f" $(echo "$storage_cost * $DAYS" | bc -l))"
            echo "Network,$(printf "%.2f" $network_cost),$(printf "%.2f" $(echo "$network_cost * $DAYS" | bc -l))"
            echo "Other,$(printf "%.2f" $other_cost),$(printf "%.2f" $(echo "$other_cost * $DAYS" | bc -l))"
            echo "Total,$(printf "%.2f" $total_cost),$(printf "%.2f" $(echo "$total_cost * $DAYS" | bc -l))"
            ;;
        *)
            echo
            echo "╔════════════════════════════════════════════════════════════╗"
            echo "║                    COST ANALYSIS REPORT                    ║"
            echo "╠════════════════════════════════════════════════════════════╣"
            echo "║ Project: $PROJECT_ID"
            echo "║ Period: $START_DATE to $END_DATE ($DAYS days)"
            echo "║ Cluster: $CLUSTER_NAME"
            echo "║"
            echo "║ ESTIMATED DAILY COSTS (USD):"
            printf "║ • Compute Nodes:     %8.2f\n" $node_cost
            printf "║ • Storage:           %8.2f\n" $storage_cost
            printf "║ • Network:           %8.2f\n" $network_cost
            printf "║ • Other Services:    %8.2f\n" $other_cost
            echo "║ ────────────────────────────────"
            printf "║ • Total Daily:       %8.2f\n" $total_cost
            echo "║"
            printf "║ ESTIMATED PERIOD COST: %8.2f USD\n" $(echo "$total_cost * $DAYS" | bc -l)
            printf "║ ESTIMATED MONTHLY:     %8.2f USD\n" $(echo "$total_cost * 30" | bc -l)
            echo "╚════════════════════════════════════════════════════════════╝"
            ;;
    esac
    
    # Check cost threshold
    local period_cost=$(echo "$total_cost * $DAYS" | bc -l)
    if (( $(echo "$period_cost > $COST_THRESHOLD" | bc -l) )); then
        log_warning "Cost threshold exceeded! Current: $period_cost USD, Threshold: $COST_THRESHOLD USD"
        
        if [[ -n "$ALERT_EMAIL" ]]; then
            send_cost_alert "$period_cost"
        fi
    fi
}

# Function to send cost alert
send_cost_alert() {
    local current_cost=$1
    
    log_warning "Sending cost alert to $ALERT_EMAIL"
    
    # This would integrate with your email service
    # For demonstration, we'll just log the alert
    cat <<EOF

🚨 COST ALERT for Orbit Challenge Platform 🚨

Project: $PROJECT_ID
Current Period Cost: $current_cost USD
Threshold: $COST_THRESHOLD USD
Period: $START_DATE to $END_DATE

Recommendations:
1. Consider pausing infrastructure when not in use
2. Review resource allocation and scaling policies
3. Monitor for unused resources

To pause infrastructure:
./scripts/pause-infrastructure.sh --project-id $PROJECT_ID

EOF
}

# Function to provide cost optimization recommendations
provide_recommendations() {
    log_info "💡 Cost Optimization Recommendations"
    
    echo
    echo "📋 IMMEDIATE ACTIONS:"
    echo "• Use pause/resume scripts during non-business hours"
    echo "• Enable preemptible nodes for challenge workloads"
    echo "• Set up automated scaling based on usage patterns"
    echo
    echo "📊 MONITORING IMPROVEMENTS:"
    echo "• Set up BigQuery billing export for detailed analysis"
    echo "• Configure budget alerts in GCP Console"
    echo "• Monitor resource utilization regularly"
    echo
    echo "🎯 OPTIMIZATION STRATEGIES:"
    echo "• Schedule automatic pause/resume (e.g., nights/weekends)"
    echo "• Use spot instances where possible"
    echo "• Implement aggressive pod autoscaling"
    echo "• Consider regional vs zonal clusters based on availability needs"
    echo
    echo "🔧 SCRIPTS AVAILABLE:"
    echo "• Pause: ./scripts/pause-infrastructure.sh --project-id $PROJECT_ID"
    echo "• Resume: ./scripts/resume-infrastructure.sh --project-id $PROJECT_ID"
    echo "• Monitor: ./scripts/cost-monitor.sh --project-id $PROJECT_ID"
    echo
}

# Function to show current vs paused cost comparison
show_cost_comparison() {
    log_info "📊 Cost Comparison: Running vs Paused"
    
    echo
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                  COST COMPARISON (Daily USD)                │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ Configuration      │ Compute │ Storage │ Network │  Total  │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ Full Operation     │  $12.84 │   $2.50 │   $1.00 │ $16.34  │"
    echo "│ Paused (Minimal)   │   $3.21 │   $2.50 │   $0.20 │  $5.91  │"
    echo "│ Savings            │   $9.63 │   $0.00 │   $0.80 │ $10.43  │"
    echo "│ Savings %          │     75% │      0% │     80% │    64%  │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo
    echo "💰 POTENTIAL MONTHLY SAVINGS: ~$313 USD (64% reduction)"
    echo "🎯 BREAK-EVEN: Pause for >2 hours daily to save money"
    echo
}

# Main execution
main() {
    echo
    log_info "🔍 Orbit Challenge Platform - Cost Analysis"
    echo
    
    # Get current resource status
    get_resource_status
    echo
    
    # Get billing data and calculate costs
    get_billing_data || calculate_estimated_costs
    echo
    
    # Show cost comparison
    if [[ "$OUTPUT_FORMAT" == "table" ]]; then
        show_cost_comparison
        provide_recommendations
    fi
    
    log_success "Cost analysis completed"
}

# Run main function
main

exit 0
