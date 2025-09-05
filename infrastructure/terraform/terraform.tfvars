# GCP Project Configuration
project_id = "smart-pipeline"
region     = "us-central1"
zone       = "us-central1-a"

# Environment Configuration
environment = "dev"

# Cluster Configuration
cluster_name = "orbit-challenge-cluster"

# System Node Pool (for system components) - Upgraded to 4 core
system_node_count        = 1
system_node_machine_type = "e2-standard-4" # 4 vCPU each = 4 vCPU total

# Challenge Node Pool (for challenge workloads) - 8 nodes autoscale to 10
challenge_node_count        = 8
challenge_node_machine_type = "e2-standard-4" # 4 vCPU each = 32 vCPU base, 40 vCPU max

# Network Configuration
network_name = "orbit-vpc"
subnet_name  = "orbit-subnet"
subnet_cidr  = "10.0.0.0/16"

# Auto-scaling Configuration (CRITICAL for budget control)
system_auto_scaling_min    = 2
system_auto_scaling_max    = 2  # Keep system nodes fixed
challenge_auto_scaling_min = 5  # Minimum challenge nodes
challenge_auto_scaling_max = 11 # Maximum 11 × 4 = 44 vCPU for challenges

# Challenge Configuration
max_challenge_pods     = 50
challenge_ttl          = "30m"
challenge_cpu_limit    = "500m"
challenge_memory_limit = "512Mi"

# CPU Budget Enforcement
total_cpu_budget             = 50
system_cpu_allocation        = 4  # 2 × e2-standard-2
max_challenge_cpu_allocation = 44 # 11 × e2-standard-4

# Cost Optimization
enable_preemptible = true

# GitHub Actions Configuration
github_actions_sa_email = "orbit-github-actions@smart-pipeline.iam.gserviceaccount.com"