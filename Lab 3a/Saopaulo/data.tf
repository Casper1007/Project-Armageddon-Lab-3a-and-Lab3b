# Reads outputs from the Tokyo (shinjuku) Terraform state for cross-region wiring
# Set use_tokyo_remote_state = true only when S3 access is available.

data "terraform_remote_state" "tokyo" {
  count   = var.use_tokyo_remote_state ? 1 : 0
  backend = "s3"
  config = {
    bucket = var.tokyo_state_bucket
    key    = var.tokyo_state_key
    region = var.tokyo_state_region
  }
}

locals {
  tokyo_vpc_cidr     = var.use_tokyo_remote_state ? data.terraform_remote_state.tokyo[0].outputs.tokyo_vpc_cidr : var.tokyo_vpc_cidr
  tokyo_rds_endpoint = var.use_tokyo_remote_state ? data.terraform_remote_state.tokyo[0].outputs.tokyo_rds_endpoint : var.tokyo_rds_endpoint
  tokyo_rds_port     = var.use_tokyo_remote_state ? try(data.terraform_remote_state.tokyo[0].outputs.tokyo_rds_port, 3306) : var.tokyo_rds_port
}
