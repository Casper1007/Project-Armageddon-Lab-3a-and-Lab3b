# ============================================================================
# Lab 3B — Audit Evidence & Logging (São Paulo)
# ============================================================================
# Purpose: Create audit trail for compute-only region
# Note: Logs are stored in Tokyo (data residency), only CloudTrail config here

# ============================================================================
# CloudTrail — Change Evidence (São Paulo)
# ============================================================================

resource "aws_cloudtrail" "liberdade_trail_saopaulo" {
  name                          = "liberdade-audit-trail-saopaulo"
  s3_bucket_name                = "chrisbarm-cloudtrail-logs-${local.tokyo_account_id}"
  s3_key_prefix                 = "saopaulo"
  include_global_service_events = false  # Tokyo handles global events
  is_multi_region_trail         = false
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = {
    Name       = "liberdade-audit-trail-saopaulo"
    Purpose    = "Change Trail Evidence"
    Region     = "sa-east-1"
    Compliance = "APPI"
  }
}

# ============================================================================
# VPC Flow Logs — Network Corridor Proof (São Paulo)
# ============================================================================

resource "aws_flow_log" "liberdade_vpc_flowlog" {
  vpc_id               = aws_vpc.liberdade_vpc01.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = "arn:aws:s3:::chrisbarm-flowlogs-${local.tokyo_account_id}"

  tags = {
    Name       = "liberdade-vpc-flowlog-saopaulo"
    Purpose    = "Network Corridor Evidence"
    Compliance = "APPI"
  }
}

# ============================================================================
# Data Source for Account ID
# ============================================================================

data "aws_caller_identity" "saopaulo_current" {}

locals {
  tokyo_account_id = data.aws_caller_identity.saopaulo_current.account_id
}
