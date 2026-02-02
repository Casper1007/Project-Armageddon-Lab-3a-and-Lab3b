# ============================================================================
# Lab 3B — Audit Evidence & Regulator-Ready Logging
# ============================================================================
# Purpose: Create immutable audit trail for APPI compliance
# Evidence: Data residency, access trail, change trail, network proof, edge security

# ============================================================================
# S3 Buckets for Audit Logs (Tokyo only — Data Residency)
# ============================================================================

# CloudTrail Bucket (Tokyo)
resource "aws_s3_bucket" "chrisbarm_cloudtrail_bucket" {
  bucket = "chrisbarm-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"
  tags = {
    Name        = "chrisbarm-cloudtrail-logs"
    Purpose     = "Audit Evidence - Change Trail"
    Compliance  = "APPI"
    DataClass   = "AuditLog"
  }
}

resource "aws_s3_bucket_versioning" "chrisbarm_cloudtrail_versioning" {
  bucket = aws_s3_bucket.chrisbarm_cloudtrail_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "chrisbarm_cloudtrail_lifecycle" {
  bucket = aws_s3_bucket.chrisbarm_cloudtrail_bucket.id

  rule {
    id     = "archive-old-trails"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 2555  # 7 years for compliance
    }
  }
}

resource "aws_s3_bucket_policy" "chrisbarm_cloudtrail_policy" {
  bucket = aws_s3_bucket.chrisbarm_cloudtrail_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.chrisbarm_cloudtrail_bucket.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.chrisbarm_cloudtrail_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# CloudFront Logs Bucket (Tokyo)
resource "aws_s3_bucket" "chrisbarm_cloudfront_logs_bucket" {
  bucket = "chrisbarm-cloudfront-logs-${data.aws_caller_identity.current.account_id}"
  tags = {
    Name        = "chrisbarm-cloudfront-logs"
    Purpose     = "Audit Evidence - Edge Access Trail"
    Compliance  = "APPI"
    DataClass   = "AccessLog"
  }
}

resource "aws_s3_bucket_versioning" "chrisbarm_cloudfront_logs_versioning" {
  bucket = aws_s3_bucket.chrisbarm_cloudfront_logs_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "chrisbarm_cloudfront_logs_ownership" {
  bucket = aws_s3_bucket.chrisbarm_cloudfront_logs_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "chrisbarm_cloudfront_logs_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.chrisbarm_cloudfront_logs_ownership]
  bucket     = aws_s3_bucket.chrisbarm_cloudfront_logs_bucket.id
  acl        = "private"
}

# WAF Logs Bucket (Tokyo)
resource "aws_s3_bucket" "chrisbarm_waf_logs_bucket" {
  bucket = "chrisbarm-waf-logs-${data.aws_caller_identity.current.account_id}"
  tags = {
    Name        = "chrisbarm-waf-logs"
    Purpose     = "Audit Evidence - Security Events"
    Compliance  = "APPI"
    DataClass   = "SecurityLog"
  }
}

resource "aws_s3_bucket_versioning" "chrisbarm_waf_logs_versioning" {
  bucket = aws_s3_bucket.chrisbarm_waf_logs_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# VPC Flow Logs Bucket (Tokyo)
resource "aws_s3_bucket" "chrisbarm_flowlogs_bucket" {
  bucket = "chrisbarm-flowlogs-${data.aws_caller_identity.current.account_id}"
  tags = {
    Name        = "chrisbarm-flowlogs"
    Purpose     = "Audit Evidence - Network Corridor Proof"
    Compliance  = "APPI"
    DataClass   = "FlowLog"
  }
}

resource "aws_s3_bucket_versioning" "chrisbarm_flowlogs_versioning" {
  bucket = aws_s3_bucket.chrisbarm_flowlogs_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ============================================================================
# CloudTrail — Change Evidence (Tokyo)
# ============================================================================

resource "aws_cloudtrail" "chrisbarm_trail_tokyo" {
  name                          = "chrisbarm-audit-trail-tokyo"
  s3_bucket_name                = aws_s3_bucket.chrisbarm_cloudtrail_bucket.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true  # Immutability proof

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = {
    Name       = "chrisbarm-audit-trail-tokyo"
    Purpose    = "Change Trail Evidence"
    Region     = "ap-northeast-1"
    Compliance = "APPI"
  }

  depends_on = [aws_s3_bucket_policy.chrisbarm_cloudtrail_policy]
}

# ============================================================================
# VPC Flow Logs — Network Corridor Proof (Tokyo)
# ============================================================================

resource "aws_flow_log" "chrisbarm_vpc_flowlog" {
  vpc_id               = aws_vpc.chrisbarm_vpc01.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = aws_s3_bucket.chrisbarm_flowlogs_bucket.arn

  tags = {
    Name       = "chrisbarm-vpc-flowlog-tokyo"
    Purpose    = "Network Corridor Evidence"
    Compliance = "APPI"
  }
}

# ============================================================================
# Data Source for Account ID
# ============================================================================

data "aws_caller_identity" "current" {}
