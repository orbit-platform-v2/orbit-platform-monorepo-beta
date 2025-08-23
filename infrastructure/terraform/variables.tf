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
  default     = 2
}

variable "challenge_node_count" {
  description = "Initial number of nodes in the challenge node pool"
  type        = number
  default     = 10
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