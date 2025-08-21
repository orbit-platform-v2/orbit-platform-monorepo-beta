# GCP Project Configuration
project_id = "smart-pipeline"
region     = "us-central1"
zone       = "us-central1-a"

# Environment Configuration
environment = "dev"

# Cluster Configuration
cluster_name = "orbit-challenge-cluster"
node_count   = 2

# Network Configuration
network_name = "orbit-vpc"
subnet_name  = "orbit-subnet"
subnet_cidr  = "10.0.0.0/16"

# Challenge Configuration
max_challenge_pods = 50
challenge_ttl      = "30m"
challenge_cpu_limit = "500m"

# Cost Optimization
enable_preemptible = true
auto_scaling_min   = 1
auto_scaling_max   = 10
