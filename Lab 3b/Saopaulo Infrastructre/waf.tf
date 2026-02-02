# ============================================================================
# Lab 3B — WAF Security Evidence
# ============================================================================
# Purpose: Block malicious traffic and create audit evidence of security events
# CloudFront is global, so WAF must be in us-east-1

# ============================================================================
# WAF Web ACL for CloudFront (us-east-1)
# ============================================================================

resource "aws_wafv2_web_acl" "liberdade_waf_acl" {
  provider = aws.us_east_1  # CloudFront requires us-east-1
  name     = "liberdade-waf-acl"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rule 1: Rate limiting (DDoS protection)
  rule {
    name     = "RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: AWS Managed Rules - Core Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: AWS Managed Rules - Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "liberdadeWafAcl"
    sampled_requests_enabled   = true
  }

  tags = {
    Name       = "liberdade-waf-acl"
    Purpose    = "Security Evidence"
    Compliance = "APPI"
  }
}

# ============================================================================
# WAF Logging Configuration
# ============================================================================

# CloudWatch Log Group for WAF logs
resource "aws_cloudwatch_log_group" "liberdade_waf_logs" {
  provider          = aws.us_east_1
  name              = "aws-waf-logs-liberdade"
  retention_in_days = 90

  tags = {
    Name       = "liberdade-waf-logs"
    Purpose    = "Security Evidence - WAF Events"
    Compliance = "APPI"
  }
}

# WAF Logging Configuration
resource "aws_wafv2_web_acl_logging_configuration" "liberdade_waf_logging" {
  provider                = aws.us_east_1
  resource_arn            = aws_wafv2_web_acl.liberdade_waf_acl.arn
  log_destination_configs = [aws_cloudwatch_log_group.liberdade_waf_logs.arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}

# ============================================================================
# Associate WAF with CloudFront
# ============================================================================
# WAF association is done in main.tf via web_acl_id parameter
