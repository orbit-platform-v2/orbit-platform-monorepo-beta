# Makefile for Orbit Challenge Platform Infrastructure
.PHONY: help setup destroy plan apply validate clean check-deps

# Default target
help: ## Show this help message
	@echo "Orbit Challenge Platform Infrastructure Management"
	@echo ""
	@echo "Usage: make [target] [VARS]"
	@echo ""
	@echo "Variables:"
	@echo "  PROJECT_ID=<gcp-project-id>    Required: GCP Project ID"
	@echo "  REGION=<region>                Optional: GCP Region (default: us-central1)"
	@echo "  CLUSTER_NAME=<name>            Optional: Cluster name (default: orbit-challenge-cluster)"
	@echo "  ENVIRONMENT=<env>              Optional: Environment (default: dev)"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Variables with defaults
PROJECT_ID ?= 
REGION ?= us-central1
CLUSTER_NAME ?= orbit-challenge-cluster
ENVIRONMENT ?= dev

# Validate required variables
check-project-id:
	@if [ -z "$(PROJECT_ID)" ]; then \
		echo "Error: PROJECT_ID is required"; \
		echo "Usage: make target PROJECT_ID=your-gcp-project-id"; \
		exit 1; \
	fi

check-deps: ## Check if required tools are installed
	@echo "Checking dependencies..."
	@command -v gcloud >/dev/null 2>&1 || { echo "gcloud CLI is required but not installed"; exit 1; }
	@command -v terraform >/dev/null 2>&1 || { echo "Terraform is required but not installed"; exit 1; }
	@command -v ansible >/dev/null 2>&1 || { echo "Ansible is required but not installed"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || echo "Warning: kubectl not found, will be installed by Ansible"
	@echo "✅ Dependencies check completed"

init-terraform: check-project-id ## Initialize Terraform
	@echo "Initializing Terraform..."
	@cd infrastructure/terraform && terraform init
	@echo "✅ Terraform initialized"

validate-terraform: init-terraform ## Validate Terraform configuration
	@echo "Validating Terraform configuration..."
	@cd infrastructure/terraform && terraform validate
	@echo "✅ Terraform configuration is valid"

plan: validate-terraform ## Plan infrastructure changes
	@echo "Planning infrastructure changes..."
	@cd infrastructure/terraform && terraform plan \
		-var="project_id=$(PROJECT_ID)" \
		-var="region=$(REGION)" \
		-var="cluster_name=$(CLUSTER_NAME)" \
		-var="environment=$(ENVIRONMENT)"

apply: validate-terraform ## Apply infrastructure changes
	@echo "Applying infrastructure changes..."
	@cd infrastructure/terraform && terraform apply \
		-var="project_id=$(PROJECT_ID)" \
		-var="region=$(REGION)" \
		-var="cluster_name=$(CLUSTER_NAME)" \
		-var="environment=$(ENVIRONMENT)" \
		-auto-approve
	@echo "✅ Infrastructure applied successfully"

setup-ansible: check-deps ## Setup Ansible requirements
	@echo "Installing Ansible requirements..."
	@cd infrastructure/ansible && ansible-galaxy install -r requirements.yml
	@echo "✅ Ansible requirements installed"

configure-cluster: setup-ansible apply ## Configure cluster with Ansible
	@echo "Configuring cluster with Ansible..."
	@cd infrastructure/ansible && ansible-playbook -i inventory/gcp.yaml site.yaml \
		-e project_id="$(PROJECT_ID)" \
		-e region="$(REGION)" \
		-e cluster_name="$(CLUSTER_NAME)" \
		-e environment="$(ENVIRONMENT)"
	@echo "✅ Cluster configuration completed"

setup: check-deps check-project-id ## Complete infrastructure setup (Terraform + Ansible)
	@echo "🚀 Starting complete infrastructure setup..."
	@echo "Project ID: $(PROJECT_ID)"
	@echo "Region: $(REGION)"
	@echo "Cluster: $(CLUSTER_NAME)"
	@echo "Environment: $(ENVIRONMENT)"
	@$(MAKE) apply PROJECT_ID=$(PROJECT_ID) REGION=$(REGION) CLUSTER_NAME=$(CLUSTER_NAME) ENVIRONMENT=$(ENVIRONMENT)
	@$(MAKE) configure-cluster PROJECT_ID=$(PROJECT_ID) REGION=$(REGION) CLUSTER_NAME=$(CLUSTER_NAME) ENVIRONMENT=$(ENVIRONMENT)
	@echo "🎉 Infrastructure setup completed successfully!"

verify: check-project-id ## Verify infrastructure deployment
	@echo "Verifying infrastructure deployment..."
	@gcloud container clusters get-credentials $(CLUSTER_NAME) --region $(REGION) --project $(PROJECT_ID)
	@echo "Cluster nodes:"
	@kubectl get nodes
	@echo "Namespaces:"
	@kubectl get namespaces | grep orbit || echo "No orbit namespaces found"
	@echo "System pods:"
	@kubectl get pods -n kube-system | head -10
	@echo "✅ Verification completed"

destroy-plan: check-project-id ## Plan infrastructure destruction
	@echo "Planning infrastructure destruction..."
	@cd infrastructure/terraform && terraform plan -destroy \
		-var="project_id=$(PROJECT_ID)" \
		-var="region=$(REGION)" \
		-var="cluster_name=$(CLUSTER_NAME)" \
		-var="environment=$(ENVIRONMENT)"

destroy: check-project-id ## Destroy infrastructure (WARNING: This will delete everything!)
	@echo "⚠️  WARNING: This will destroy ALL infrastructure resources!"
	@echo "Project ID: $(PROJECT_ID)"
	@echo "Region: $(REGION)"
	@echo "Cluster: $(CLUSTER_NAME)"
	@read -p "Are you sure? Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || exit 1
	@echo "Destroying infrastructure..."
	@cd infrastructure/terraform && terraform destroy \
		-var="project_id=$(PROJECT_ID)" \
		-var="region=$(REGION)" \
		-var="cluster_name=$(CLUSTER_NAME)" \
		-var="environment=$(ENVIRONMENT)" \
		-auto-approve
	@echo "🗑️  Infrastructure destroyed"

clean: ## Clean up local files and state
	@echo "Cleaning up local files..."
	@cd infrastructure/terraform && rm -f terraform.tfstate.backup
	@cd infrastructure/terraform && rm -rf .terraform.lock.hcl
	@echo "✅ Cleanup completed"

status: check-project-id ## Show infrastructure status
	@echo "Infrastructure Status for $(PROJECT_ID)"
	@echo "=================================="
	@echo "Terraform state:"
	@cd infrastructure/terraform && terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[] | select(.type == "google_container_cluster") | .values.name' 2>/dev/null || echo "No cluster found in state"
	@echo ""
	@echo "GCP Resources:"
	@gcloud container clusters list --project=$(PROJECT_ID) --filter="name:$(CLUSTER_NAME)" 2>/dev/null || echo "No clusters found"
	@echo ""
	@echo "Kubectl context:"
	@kubectl config current-context 2>/dev/null || echo "No kubectl context set"

logs: check-project-id ## Show recent cluster logs
	@echo "Recent cluster events:"
	@gcloud container clusters get-credentials $(CLUSTER_NAME) --region $(REGION) --project $(PROJECT_ID) 2>/dev/null || true
	@kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20 2>/dev/null || echo "Cannot retrieve events"

cost: check-project-id ## Show estimated costs (requires billing export)
	@echo "Infrastructure costs (approximate):"
	@echo "Note: Enable billing export to BigQuery for detailed cost analysis"
	@gcloud billing budgets list --billing-account=$(shell gcloud beta billing accounts list --format="value(name)" 2>/dev/null | head -1) 2>/dev/null || echo "Cannot retrieve billing information"

# Development targets
dev-setup: ## Setup development environment
	@$(MAKE) setup PROJECT_ID=$(PROJECT_ID) ENVIRONMENT=dev CLUSTER_NAME=orbit-dev-cluster

prod-setup: ## Setup production environment
	@$(MAKE) setup PROJECT_ID=$(PROJECT_ID) ENVIRONMENT=prod CLUSTER_NAME=orbit-prod-cluster

staging-setup: ## Setup staging environment
	@$(MAKE) setup PROJECT_ID=$(PROJECT_ID) ENVIRONMENT=staging CLUSTER_NAME=orbit-staging-cluster

# Quick aliases
up: setup ## Alias for setup
down: destroy ## Alias for destroy
check: verify ## Alias for verify

# Example usage
example: ## Show example usage
	@echo "Example commands:"
	@echo ""
	@echo "# Setup development environment"
	@echo "make setup PROJECT_ID=my-gcp-project"
	@echo ""
	@echo "# Setup production environment in us-west1"
	@echo "make setup PROJECT_ID=my-gcp-project ENVIRONMENT=prod REGION=us-west1"
	@echo ""
	@echo "# Plan changes only"
	@echo "make plan PROJECT_ID=my-gcp-project"
	@echo ""
	@echo "# Verify deployment"
	@echo "make verify PROJECT_ID=my-gcp-project"
	@echo ""
	@echo "# Destroy infrastructure"
	@echo "make destroy PROJECT_ID=my-gcp-project"
