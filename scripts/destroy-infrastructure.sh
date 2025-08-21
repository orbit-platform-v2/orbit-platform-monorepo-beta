#!/bin/bash

# Orbit Challenge Platform Infrastructure Teardown Script
# This script safely destroys the infrastructure created by setup-infrastructure.sh

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
TERRAFORM_DIR="$PROJECT_ROOT/infrastructure/terraform"

# Default values
ENVIRONMENT="dev"
DRY_RUN=false
FORCE=false

# Functions
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

Destroy Orbit Challenge Platform Infrastructure

OPTIONS:
    -e, --environment    Environment (dev, staging, prod) [default: dev]
    -p, --project-id     GCP Project ID (required)
    -r, --region         GCP Region [default: us-central1]
    -c, --cluster-name   GKE Cluster name [default: orbit-challenge-cluster]
    --dry-run           Show what would be destroyed without executing
    --force             Skip confirmation prompts
    -h, --help          Show this help message

EXAMPLES:
    $0 --project-id my-gcp-project
    $0 --project-id my-gcp-project --environment prod --force
    $0 --project-id my-gcp-project --dry-run

WARNING:
    This will destroy ALL infrastructure resources created by the setup script.
    This action cannot be undone!

EOF
}

confirm_destruction() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return
    fi
    
    echo -e "${RED}WARNING: This will destroy the following resources:${NC}"
    echo "  - GKE Cluster: $CLUSTER_NAME"
    echo "  - VPC Network and subnets"
    echo "  - Load balancer and IP addresses"
    echo "  - Storage buckets and data"
    echo "  - Container registry images"
    echo "  - Monitoring resources"
    echo "  - All associated data"
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    read -p "Are you absolutely sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
}

backup_important_data() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run mode - skipping data backup"
        return
    fi
    
    log_info "Creating backup of important data..."
    
    # Create backup directory
    BACKUP_DIR="$PROJECT_ROOT/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Export Kubernetes resources
    if kubectl cluster-info &> /dev/null; then
        log_info "Backing up Kubernetes resources..."
        kubectl get all --all-namespaces -o yaml > "$BACKUP_DIR/all-resources.yaml"
        kubectl get configmaps --all-namespaces -o yaml > "$BACKUP_DIR/configmaps.yaml"
        kubectl get secrets --all-namespaces -o yaml > "$BACKUP_DIR/secrets.yaml"
        kubectl get pv,pvc --all-namespaces -o yaml > "$BACKUP_DIR/volumes.yaml"
    fi
    
    # Copy Terraform state
    if [[ -f "$TERRAFORM_DIR/terraform.tfstate" ]]; then
        log_info "Backing up Terraform state..."
        cp "$TERRAFORM_DIR/terraform.tfstate" "$BACKUP_DIR/"
    fi
    
    log_success "Backup created at: $BACKUP_DIR"
}

destroy_kubernetes_resources() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run mode - would delete Kubernetes resources"
        return
    fi
    
    log_info "Cleaning up Kubernetes resources..."
    
    # Configure kubectl
    if gcloud container clusters describe "$CLUSTER_NAME" --region "$REGION" --project "$PROJECT_ID" &> /dev/null; then
        gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION" --project "$PROJECT_ID"
        
        # Delete PVCs to avoid orphaned disks
        log_info "Deleting PersistentVolumeClaims..."
        kubectl delete pvc --all --all-namespaces --timeout=300s || true
        
        # Delete LoadBalancer services to clean up external IPs
        log_info "Deleting LoadBalancer services..."
        kubectl delete services --all-namespaces --field-selector spec.type=LoadBalancer --timeout=300s || true
        
        # Delete ingress resources
        log_info "Deleting Ingress resources..."
        kubectl delete ingress --all --all-namespaces --timeout=300s || true
    else
        log_warning "Cluster not found or not accessible, skipping Kubernetes cleanup"
    fi
}

destroy_terraform() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run mode - would run terraform destroy"
        return
    fi
    
    log_info "Destroying Terraform infrastructure..."
    
    cd "$TERRAFORM_DIR"
    
    # Plan destruction
    log_info "Planning infrastructure destruction..."
    terraform plan -destroy \
        -var="project_id=$PROJECT_ID" \
        -var="region=$REGION" \
        -var="cluster_name=$CLUSTER_NAME" \
        -var="environment=$ENVIRONMENT"
    
    # Destroy
    log_info "Destroying infrastructure..."
    terraform destroy \
        -var="project_id=$PROJECT_ID" \
        -var="region=$REGION" \
        -var="cluster_name=$CLUSTER_NAME" \
        -var="environment=$ENVIRONMENT" \
        -auto-approve
    
    log_success "Terraform destruction completed"
}

cleanup_gcp_resources() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run mode - would clean up remaining GCP resources"
        return
    fi
    
    log_info "Cleaning up remaining GCP resources..."
    
    # Delete any remaining compute disks
    log_info "Checking for orphaned compute disks..."
    DISKS=$(gcloud compute disks list --project="$PROJECT_ID" --filter="name~gke-$CLUSTER_NAME" --format="value(name,zone)" 2>/dev/null || true)
    if [[ -n "$DISKS" ]]; then
        while IFS= read -r line; do
            DISK_NAME=$(echo "$line" | cut -d' ' -f1)
            ZONE=$(echo "$line" | cut -d' ' -f2)
            log_warning "Deleting orphaned disk: $DISK_NAME in $ZONE"
            gcloud compute disks delete "$DISK_NAME" --zone="$ZONE" --project="$PROJECT_ID" --quiet || true
        done <<< "$DISKS"
    fi
    
    # Delete any remaining forwarding rules
    log_info "Checking for orphaned forwarding rules..."
    RULES=$(gcloud compute forwarding-rules list --project="$PROJECT_ID" --filter="name~$CLUSTER_NAME" --format="value(name,region)" 2>/dev/null || true)
    if [[ -n "$RULES" ]]; then
        while IFS= read -r line; do
            RULE_NAME=$(echo "$line" | cut -d' ' -f1)
            REGION_NAME=$(echo "$line" | cut -d' ' -f2)
            log_warning "Deleting orphaned forwarding rule: $RULE_NAME"
            if [[ -n "$REGION_NAME" ]]; then
                gcloud compute forwarding-rules delete "$RULE_NAME" --region="$REGION_NAME" --project="$PROJECT_ID" --quiet || true
            else
                gcloud compute forwarding-rules delete "$RULE_NAME" --global --project="$PROJECT_ID" --quiet || true
            fi
        done <<< "$RULES"
    fi
    
    log_success "GCP cleanup completed"
}

verify_destruction() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run mode - skipping destruction verification"
        return
    fi
    
    log_info "Verifying infrastructure destruction..."
    
    # Check if cluster still exists
    if gcloud container clusters describe "$CLUSTER_NAME" --region "$REGION" --project "$PROJECT_ID" &> /dev/null; then
        log_error "Cluster still exists! Destruction may have failed."
        return 1
    fi
    
    # Check for remaining resources
    log_info "Checking for remaining resources..."
    REMAINING_RESOURCES=$(gcloud compute instances list --project="$PROJECT_ID" --filter="name~gke-$CLUSTER_NAME" --format="value(name)" 2>/dev/null || true)
    if [[ -n "$REMAINING_RESOURCES" ]]; then
        log_warning "Some compute instances may still exist:"
        echo "$REMAINING_RESOURCES"
    fi
    
    log_success "Destruction verification completed"
}

main() {
    log_info "Starting Orbit Challenge Platform Infrastructure Teardown"
    log_info "Environment: $ENVIRONMENT"
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Cluster Name: $CLUSTER_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi
    
    confirm_destruction
    backup_important_data
    destroy_kubernetes_resources
    destroy_terraform
    cleanup_gcp_resources
    verify_destruction
    
    log_success "Infrastructure teardown completed!"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        cat << EOF

🗑️  Orbit Challenge Platform Infrastructure has been destroyed!

What was removed:
- GKE Cluster and node pools
- VPC network and subnets
- Load balancers and IP addresses
- Storage buckets and data
- Container registry images
- Monitoring resources

Backup location: $PROJECT_ROOT/backups/

Note: Some resources may take a few minutes to fully delete.
You can verify in the GCP Console that all resources have been removed.

EOF
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
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

# Validate inputs
if [[ -z "$PROJECT_ID" ]]; then
    log_error "Project ID is required. Use --project-id option."
    usage
    exit 1
fi

# Set defaults
REGION="${REGION:-us-central1}"
CLUSTER_NAME="${CLUSTER_NAME:-orbit-challenge-cluster}"

# Run main function
main
