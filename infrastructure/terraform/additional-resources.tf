# SSL Certificate for Load Balancer (if domain is provided)
resource "google_compute_managed_ssl_certificate" "platform_ssl" {
  count = length(var.ssl_certificate_domains) > 0 ? 1 : 0
  name  = "${var.cluster_name}-ssl-cert"

  managed {
    domains = var.ssl_certificate_domains
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Cloud DNS Zone (optional)
resource "google_dns_managed_zone" "platform_zone" {
  count       = var.domain_name != "" ? 1 : 0
  name        = "${var.cluster_name}-zone"
  dns_name    = "${var.domain_name}."
  description = "DNS zone for Orbit Challenge Platform"

  labels = {
    environment = var.environment
    project     = "orbit-challenge"
  }
}

# DNS A record for the platform
resource "google_dns_record_set" "platform_a" {
  count        = var.domain_name != "" ? 1 : 0
  name         = var.domain_name
  managed_zone = google_dns_managed_zone.platform_zone[0].name
  type         = "A"
  ttl          = 300

  rrdatas = [google_compute_global_address.lb_ip.address]
}

# Cloud Build trigger for automated deployments (optional)
resource "google_cloudbuild_trigger" "deploy_trigger" {
  count    = var.environment == "prod" ? 1 : 0
  name     = "${var.cluster_name}-deploy"
  filename = "cloudbuild.yaml"

github {
  owner = "orbit-platform-v2"
  name  = "orbit-platform-monorepo-beta"  # Your actual repo name
}

  substitutions = {
    _CLUSTER_NAME = var.cluster_name
    _REGION       = var.region
    _PROJECT_ID   = var.project_id
  }
}

# Container Registry (being replaced by Artifact Registry)
resource "google_container_registry" "registry" {
  project  = var.project_id
  location = "US"
}

# Artifact Registry for container images
resource "google_artifact_registry_repository" "docker_repo" {
  location      = var.region
  repository_id = "${var.cluster_name}-docker"
  description   = "Docker repository for challenge images"
  format        = "DOCKER"

  labels = {
    environment = var.environment
    project     = "orbit-challenge"
  }
}

# Service Account for Cloud Build
resource "google_service_account" "cloudbuild_sa" {
  account_id   = "${var.cluster_name}-cloudbuild"
  display_name = "Cloud Build Service Account"
  description  = "Service account for Cloud Build operations"
}

# IAM bindings for Cloud Build
resource "google_project_iam_member" "cloudbuild_roles" {
  for_each = toset([
    "roles/container.developer",
    "roles/cloudbuild.builds.builder",
    "roles/source.reader"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# Monitoring workspace
resource "google_monitoring_workspace" "workspace" {
  count                      = var.enable_monitoring ? 1 : 0
  provider                   = google-beta
  workspace_id              = var.project_id
  notification_channels     = []
  
  labels = {
    environment = var.environment
  }
}

# Log-based metrics for monitoring
resource "google_logging_metric" "pod_creation_metric" {
  count  = var.enable_monitoring ? 1 : 0
  name   = "orbit_pod_creation_rate"
  filter = "resource.type=\"k8s_pod\" AND labels.\"k8s-pod/app\"=\"challenge-pod\""
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Challenge Pod Creation Rate"
  }

  extraction {
    count = true
  }
}

# Storage bucket for backups and logs
resource "google_storage_bucket" "platform_storage" {
  name     = "${var.project_id}-${var.cluster_name}-storage"
  location = var.region

  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.backup_retention_days
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    environment = var.environment
    purpose     = "platform-storage"
  }
}

# IAM for storage bucket
resource "google_storage_bucket_iam_member" "platform_storage_admin" {
  bucket = google_storage_bucket.platform_storage.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Outputs for additional resources
output "artifact_registry_url" {
  description = "Artifact Registry repository URL"
  value       = google_artifact_registry_repository.docker_repo.name
}

output "storage_bucket_name" {
  description = "Storage bucket name"
  value       = google_storage_bucket.platform_storage.name
}

output "ssl_certificate_name" {
  description = "SSL certificate name (if created)"
  value       = length(google_compute_managed_ssl_certificate.platform_ssl) > 0 ? google_compute_managed_ssl_certificate.platform_ssl[0].name : ""
}

output "dns_zone_name" {
  description = "DNS zone name (if created)"
  value       = length(google_dns_managed_zone.platform_zone) > 0 ? google_dns_managed_zone.platform_zone[0].name : ""
}
