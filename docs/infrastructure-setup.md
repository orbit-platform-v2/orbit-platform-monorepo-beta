# Infrastructure Setup Guide

This guide walks you through setting up the complete infrastructure for the Orbit DevOps Challenge Platform.

## 📋 Prerequisites

### Required Tools

1. **Google Cloud SDK (gcloud)**
   ```bash
   # Install on Linux/macOS
   curl https://sdk.cloud.google.com | bash
   exec -l $SHELL
   
   # Install on Windows
   # Download from https://cloud.google.com/sdk/docs/install
   ```

2. **Terraform (>= 1.0)**
   ```bash
   # Install on Linux/macOS
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   
   # Install on Windows (using Chocolatey)
   choco install terraform
   ```

3. **Ansible (>= 2.9)**
   ```bash
   # Install on Linux/macOS
   pip3 install ansible
   
   # Install on Windows (WSL recommended)
   pip install ansible
   ```

4. **kubectl**
   ```bash
   # Install on Linux/macOS
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   chmod +x kubectl
   sudo mv kubectl /usr/local/bin/
   
   # Install on Windows
   choco install kubernetes-cli
   ```

### GCP Setup

1. **Create GCP Project**
   ```bash
   gcloud projects create YOUR_PROJECT_ID
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Enable Billing**
   - Go to GCP Console → Billing
   - Link a billing account to your project

3. **Authenticate**
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

4. **Set Default Region/Zone**
   ```bash
   gcloud config set compute/region us-central1
   gcloud config set compute/zone us-central1-a
   ```

## 🚀 Quick Setup

### Option 1: Automated Setup (Recommended)

**Linux/macOS:**
```bash
./scripts/setup-infrastructure.sh --project-id YOUR_PROJECT_ID
```

**Windows (PowerShell):**
```powershell
.\scripts\setup-infrastructure.ps1 -ProjectId "YOUR_PROJECT_ID"
```

### Option 2: Manual Step-by-Step Setup

#### Step 1: Configure Terraform

1. Navigate to terraform directory:
   ```bash
   cd infrastructure/terraform
   ```

2. Copy and customize variables:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. Initialize and apply:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

#### Step 2: Configure Cluster with Ansible

1. Navigate to ansible directory:
   ```bash
   cd infrastructure/ansible
   ```

2. Install requirements:
   ```bash
   ansible-galaxy install -r requirements.yml
   ```

3. Run playbook:
   ```bash
   ansible-playbook -i inventory/gcp.yaml site.yaml \
     -e project_id=YOUR_PROJECT_ID \
     -e region=us-central1 \
     -e cluster_name=orbit-challenge-cluster
   ```

## 🔧 Configuration Options

### Terraform Variables

Key variables you can customize in `terraform.tfvars`:

```hcl
# Project configuration
project_id   = "your-gcp-project-id"
region       = "us-central1"
cluster_name = "orbit-challenge-cluster"
environment  = "dev"

# Node configuration
system_node_count    = 2
challenge_node_count = 3

# Platform configuration
max_concurrent_users = 100
pod_ttl_seconds     = 1800  # 30 minutes

# Optional: Domain configuration
domain_name = "challenges.yourdomain.com"
ssl_certificate_domains = ["challenges.yourdomain.com"]

# Feature flags
enable_monitoring      = true
enable_network_policy  = true
cost_optimization     = true
```

### Environment-Specific Configurations

#### Development Environment
```hcl
environment = "dev"
system_node_count = 1
challenge_node_count = 2
max_concurrent_users = 20
cost_optimization = true
```

#### Production Environment
```hcl
environment = "prod"
system_node_count = 3
challenge_node_count = 5
max_concurrent_users = 100
enable_monitoring = true
backup_retention_days = 30
```

## 🏗️ Infrastructure Components

### Core Resources

1. **VPC Network**
   - Private subnet for GKE nodes
   - Secondary ranges for pods and services
   - Cloud NAT for outbound internet access

2. **GKE Cluster**
   - Private cluster with authorized networks
   - Two node pools: system and challenge workloads
   - Workload Identity enabled
   - Network policies enabled

3. **Load Balancer**
   - Global HTTP(S) Load Balancer
   - SSL certificate (if domain provided)
   - Static IP address

4. **Storage & Registry**
   - Artifact Registry for container images
   - Cloud Storage bucket for backups
   - BigQuery dataset for usage analytics

### Security Features

1. **Network Security**
   - Private GKE nodes (no public IPs)
   - Network policies for pod isolation
   - Firewall rules for controlled access

2. **Access Control**
   - Service accounts with minimal permissions
   - RBAC for Kubernetes resources
   - Workload Identity for pod-to-GCP authentication

3. **Container Security**
   - Shielded GKE nodes
   - Container image scanning
   - Pod security standards

## 📊 Monitoring & Observability

### Prometheus & Grafana

The setup includes:
- Prometheus for metrics collection
- Grafana for visualization
- AlertManager for notifications

Access Grafana:
```bash
kubectl port-forward -n orbit-monitoring svc/prometheus-grafana 3000:80
# Open http://localhost:3000 (admin/admin123)
```

### Log Aggregation

Logs are automatically collected and available in:
- Google Cloud Logging
- Prometheus metrics for log-based alerts

### Custom Metrics

Key metrics tracked:
- Challenge pod creation/deletion rate
- WebSocket connection count
- Resource utilization per namespace
- User session duration

## 🔧 Maintenance Operations

### Scaling Operations

**Scale node pools:**
```bash
gcloud container clusters resize orbit-challenge-cluster \
  --num-nodes 5 \
  --node-pool challenge-pool \
  --region us-central1
```

**Update cluster:**
```bash
gcloud container clusters upgrade orbit-challenge-cluster \
  --region us-central1
```

### Backup & Recovery

**Create backup:**
```bash
# Kubernetes resources
kubectl get all --all-namespaces -o yaml > backup-$(date +%Y%m%d).yaml

# Terraform state (if using local state)
cp terraform.tfstate terraform.tfstate.backup
```

**Restore from backup:**
```bash
kubectl apply -f backup-YYYYMMDD.yaml
```

### Cost Optimization

1. **Use preemptible nodes for challenge workloads**
2. **Enable cluster autoscaling**
3. **Set appropriate pod TTLs**
4. **Monitor and clean up unused resources**

View costs:
```bash
gcloud billing budgets list
gcloud logging read "resource.type=gke_cluster" --limit=50 --format="table(timestamp,resource.labels.cluster_name,resource.labels.location)"
```

## 🚨 Troubleshooting

### Common Issues

1. **Insufficient API quotas**
   ```bash
   gcloud compute project-info describe --project=YOUR_PROJECT_ID
   # Check quotas in GCP Console
   ```

2. **Network connectivity issues**
   ```bash
   kubectl get nodes
   kubectl describe node NODE_NAME
   gcloud compute instances list
   ```

3. **Pod creation failures**
   ```bash
   kubectl get pods -n orbit-challenges
   kubectl describe pod POD_NAME -n orbit-challenges
   kubectl logs POD_NAME -n orbit-challenges
   ```

4. **Terraform state issues**
   ```bash
   terraform state list
   terraform state show RESOURCE_NAME
   terraform import RESOURCE_TYPE.NAME RESOURCE_ID
   ```

### Debug Commands

```bash
# Cluster status
kubectl cluster-info
kubectl get nodes -o wide

# Resource usage
kubectl top nodes
kubectl top pods --all-namespaces

# Network policies
kubectl get networkpolicies --all-namespaces

# Events
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Service mesh (if enabled)
kubectl get pods -n istio-system
```

## 🔄 Updates & Maintenance

### Regular Maintenance Tasks

1. **Weekly:**
   - Check cluster health
   - Review resource usage
   - Clean up old challenge pods

2. **Monthly:**
   - Update node pools
   - Review and rotate secrets
   - Update monitoring dashboards

3. **Quarterly:**
   - Upgrade Kubernetes version
   - Review and update security policies
   - Capacity planning review

### Update Procedures

**Update Terraform:**
```bash
cd infrastructure/terraform
terraform plan
terraform apply
```

**Update Ansible configuration:**
```bash
cd infrastructure/ansible
ansible-playbook -i inventory/gcp.yaml site.yaml --diff
```

## 📞 Support & Resources

### Documentation Links
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Ansible Kubernetes Collection](https://docs.ansible.com/ansible/latest/collections/kubernetes/core/)

### Getting Help
- Check logs with `kubectl logs`
- Review events with `kubectl get events`
- Use `kubectl describe` for detailed resource information
- Consult GCP Console for infrastructure-level issues

### Emergency Contacts
- Platform Team: platform-team@company.com
- On-call Engineer: +1-XXX-XXX-XXXX
- Incident Response: incidents@company.com
