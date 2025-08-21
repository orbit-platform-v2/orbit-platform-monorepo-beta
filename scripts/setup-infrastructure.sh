#!/bin/bash

# Orbit Challenge Platform Infrastructure Setup Script
# This script sets up the complete infrastructure for the platform

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
ANSIBLE_DIR="$PROJECT_ROOT/infrastructure/ansible"

# Default values
ENVIRONMENT="dev"
DRY_RUN=false
SKIP_TERRAFORM=false
SKIP_ANSIBLE=false

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

Deploy Orbit Challenge Platform Infrastructure

OPTIONS:
    -e, --environment    Environment (dev, staging, prod) [default: dev]
    -p, --project-id     GCP Project ID (required)
    -r, --region         GCP Region [default: us-central1]
    -c, --cluster-name   GKE Cluster name [default: orbit-challenge-cluster]
    --dry-run           Show what would be done without executing
    --skip-terraform    Skip Terraform deployment
    --skip-ansible      Skip Ansible configuration
    -h, --help          Show this help message

EXAMPLES:
    $0 --project-id my-gcp-project
    $0 --project-id my-gcp-project --environment prod --region us-west1
    $0 --project-id my-gcp-project --dry-run

PREREQUISITES:
    - gcloud CLI authenticated and configured
    - Terraform >= 1.0 installed
    - Ansible >= 2.9 installed
    - kubectl installed
    - Docker installed (for local development)

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check gcloud
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed"
        exit 1
    fi
    
    # Check terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed"
        exit 1
    fi
    
    # Check ansible
    if ! command -v ansible &> /dev/null; then
        log_error "Ansible is not installed"
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl is not installed, it will be installed by Ansible"
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "gcloud is not authenticated. Run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

validate_inputs() {
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use --project-id option."
        usage
        exit 1
    fi
    
    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        log_error "Environment must be one of: dev, staging, prod"
        exit 1
    fi
    
    log_info "Validating GCP project access..."
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Cannot access project $PROJECT_ID. Check project ID and permissions."
        exit 1
    fi
    
    log_success "Input validation completed"
}

setup_terraform() {
    if [[ "$SKIP_TERRAFORM" == "true" ]]; then
        log_warning "Skipping Terraform deployment"
        return
    fi
    
    log_info "Setting up Terraform..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init
    
    # Create terraform.tfvars if it doesn't exist
    if [[ ! -f "terraform.tfvars" ]]; then
        log_info "Creating terraform.tfvars from example..."
        cp terraform.tfvars.example terraform.tfvars
        
        # Update with provided values
        sed -i "s/your-gcp-project-id/$PROJECT_ID/g" terraform.tfvars
        sed -i "s/us-central1/$REGION/g" terraform.tfvars
        sed -i "s/orbit-challenge-cluster/$CLUSTER_NAME/g" terraform.tfvars
        sed -i "s/dev/$ENVIRONMENT/g" terraform.tfvars
        
        log_warning "Please review and update terraform.tfvars with your specific values"
    fi
    
    # Plan
    log_info "Planning Terraform deployment..."
    terraform plan -var="project_id=$PROJECT_ID" -var="region=$REGION" -var="cluster_name=$CLUSTER_NAME" -var="environment=$ENVIRONMENT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run mode - skipping Terraform apply"
        return
    fi
    
    # Apply
    log_info "Applying Terraform configuration..."
    terraform apply -var="project_id=$PROJECT_ID" -var="region=$REGION" -var="cluster_name=$CLUSTER_NAME" -var="environment=$ENVIRONMENT" -auto-approve
    
    log_success "Terraform deployment completed"
}

setup_ansible() {
    if [[ "$SKIP_ANSIBLE" == "true" ]]; then
        log_warning "Skipping Ansible configuration"
        return
    fi
    
    log_info "Setting up Ansible..."
    
    cd "$ANSIBLE_DIR"
    
    # Install required collections
    log_info "Installing Ansible requirements..."
    ansible-galaxy install -r requirements.yml
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run mode - skipping Ansible playbook execution"
        return
    fi
    
    # Run playbook
    log_info "Running Ansible playbook..."
    ansible-playbook -i inventory/gcp.yaml site.yaml \
        -e project_id="$PROJECT_ID" \
        -e region="$REGION" \
        -e cluster_name="$CLUSTER_NAME" \
        -e environment="$ENVIRONMENT"
    
    log_success "Ansible configuration completed"
}

verify_deployment() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run mode - skipping deployment verification"
        return
    fi
    
    log_info "Verifying deployment..."
    
    # Configure kubectl
    log_info "Configuring kubectl..."
    gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION" --project "$PROJECT_ID"
    
    # Check cluster status
    log_info "Checking cluster status..."
    kubectl get nodes
    
    # Check namespaces
    log_info "Checking namespaces..."
    kubectl get namespaces | grep orbit
    
    # Check system pods
    log_info "Checking system pods..."
    kubectl get pods -n kube-system
    
    log_success "Deployment verification completed"
}

cleanup() {
    log_info "Cleaning up temporary files..."
    # Add cleanup logic here if needed
}

main() {
    log_info "Starting Orbit Challenge Platform Infrastructure Setup"
    log_info "Environment: $ENVIRONMENT"
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Cluster Name: $CLUSTER_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi
    
    check_prerequisites
    validate_inputs
    setup_terraform
    setup_ansible
    verify_deployment
    cleanup
    
    log_success "Infrastructure setup completed successfully!"
    
    cat << EOF

🎉 Orbit Challenge Platform Infrastructure is ready!

Next steps:
1. Review the created resources in GCP Console
2. Deploy the Orbit Operator: kubectl apply -f k8s-manifests/operator/
3. Deploy the WebSocket Router: kubectl apply -f k8s-manifests/websocket-router/
4. Deploy the Backend API: kubectl apply -f k8s-manifests/backend/
5. Deploy the Frontend: kubectl apply -f k8s-manifests/frontend/

Useful commands:
- kubectl get nodes
- kubectl get namespaces
- kubectl get pods -A
- kubectl logs -n orbit-system -l app=orbit-operator

Access your cluster:
gcloud container clusters get-credentials $CLUSTER_NAME --region $REGION --project $PROJECT_ID

EOF
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
        --skip-terraform)
            SKIP_TERRAFORM=true
            shift
            ;;
        --skip-ansible)
            SKIP_ANSIBLE=true
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

# Trap to cleanup on exit
trap cleanup EXIT

# Run main function
main
