# The backend.tf file should already be configured, but verify:
# filepath: infrastructure/terraform/backend.tf
terraform {
  backend "gcs" {
    bucket = "smart-pipeline-terraform-state"
    prefix = "terraform/state"
  }
}