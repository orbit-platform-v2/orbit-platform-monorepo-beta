# Variables for Orbit DevOps Challenge Platform

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region to deploy resources"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "orbit-challenge-cluster"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "system_node_count" {
  description = "Number of nodes in the system node pool"
  type        = number
  default     = 1
}

variable "challenge_node_count" {
  description = "Initial number of nodes in the challenge node pool"
  type        = number
  default     = 8
}

variable "max_concurrent_users" {
  description = "Maximum number of concurrent users"
  type        = number
  default     = 100
}

variable "pod_ttl_seconds" {
  description = "TTL for challenge pods in seconds"
  type        = number
  default     = 1800 # 30 minutes
}

variable "enable_monitoring" {
  description = "Enable monitoring and logging"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable network policies"
  type        = bool
  default     = true
}

variable "authorized_networks" {
  description = "List of authorized networks for cluster access"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [
    {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks"
    }
  ]
}

variable "node_locations" {
  description = "List of zones for node pools"
  type        = list(string)
  default     = ["us-central1-a", "us-central1-b", "us-central1-c"]
}

variable "domain_name" {
  description = "Domain name for the platform"
  type        = string
  default     = ""
}

variable "ssl_certificate_domains" {
  description = "Domains for SSL certificate"
  type        = list(string)
  default     = []
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "cost_optimization" {
  description = "Enable cost optimization features"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  default     = "achref.messai@insat.ucar.tn"
}
# Add these variables to the end of your existing variables.tf file

variable "github_repo_owner" {
  description = "GitHub repository owner"
  type        = string
  default     = "achrefmessai01" # Update with your GitHub username
}

variable "github_repo_name" {
  description = "GitHub repository name"
  type        = string
  default     = "orbit-platform-monorepo-beta"
}

variable "github_actions_sa_email" {
  description = "GitHub Actions service account email"
  type        = string
  default     = "orbit-github-actions@smart-pipeline.iam.gserviceaccount.com"
}

# Machine type variables
variable "system_node_machine_type" {
  description = "Machine type for system node pool"
  type        = string
  default     = "e2-standard-4"
}

variable "challenge_node_machine_type" {
  description = "Machine type for challenge node pool"
  type        = string
  default     = "e2-standard-4"
}

# Network configuration
variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.0.0/16"
}

variable "pods_cidr" {
  description = "CIDR block for pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "CIDR block for services"
  type        = string
  default     = "10.2.0.0/16"
}

# Scaling configuration
variable "max_nodes_system" {
  description = "Maximum number of nodes in system pool"
  type        = number
  default     = 3
}

variable "max_nodes_challenge" {
  description = "Maximum number of nodes in challenge pool"
  type        = number
  default     = 20
}

variable "min_nodes_system" {
  description = "Minimum number of nodes in system pool"
  type        = number
  default     = 1
}

variable "min_nodes_challenge" {
  description = "Minimum number of nodes in challenge pool"
  type        = number
  default     = 0
}

# Budget enforcement
variable "enable_budget_enforcement" {
  description = "Enable budget enforcement for cost control"
  type        = bool
  default     = true
}

variable "budget_amount" {
  description = "Monthly budget amount in USD"
  type        = number
  default     = 200
}

# Resource allocation
variable "challenge_cpu_limit" {
  description = "CPU limit for each challenge container"
  type        = string
  default     = "1000m"
}

variable "challenge_memory_limit" {
  description = "Memory limit for each challenge container"
  type        = string
  default     = "1Gi"
}

variable "challenge_cpu_request" {
  description = "CPU request for each challenge container"
  type        = string
  default     = "500m"
}

variable "challenge_memory_request" {
  description = "Memory request for each challenge container"
  type        = string
  default     = "512Mi"
}

# Additional challenge configuration variables
variable "max_challenge_pods" {
  description = "Maximum number of challenge pods"
  type        = number
  default     = 50
}

variable "challenge_ttl" {
  description = "Time to live for challenge pods"
  type        = string
  default     = "30m"
}

# CPU allocation variables
variable "total_cpu_budget" {
  description = "Total CPU budget for the platform"
  type        = number
  default     = 50
}

variable "system_cpu_allocation" {
  description = "CPU allocation for system components"
  type        = number
  default     = 4
}

variable "max_challenge_cpu_allocation" {
  description = "Maximum CPU allocation for challenge workloads"
  type        = number
  default     = 44
}

# Cost optimization variables
variable "enable_preemptible" {
  description = "Enable preemptible instances for cost optimization"
  type        = bool
  default     = true
}

# Additional missing variables from terraform.tfvars
variable "zone" {
  description = "The primary GCP zone for resources"
  type        = string
  default     = "us-central1-a"
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "orbit-vpc"
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
  default     = "orbit-subnet"
}

# Auto-scaling configuration variables
variable "system_auto_scaling_min" {
  description = "Minimum number of nodes in system pool for auto-scaling"
  type        = number
  default     = 1
}

variable "system_auto_scaling_max" {
  description = "Maximum number of nodes in system pool for auto-scaling"
  type        = number
  default     = 1
}

variable "challenge_auto_scaling_min" {
  description = "Minimum number of nodes in challenge pool for auto-scaling"
  type        = number
  default     = 8
}

variable "challenge_auto_scaling_max" {
  description = "Maximum number of nodes in challenge pool for auto-scaling"
  type        = number
  default     = 10
}