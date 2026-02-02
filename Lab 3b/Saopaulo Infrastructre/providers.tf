# Sao Paulo provider (default)
provider "aws" {
  region = "sa-east-1"
}

# us-east-1 provider for CloudFront WAF (WAF for CloudFront must be in us-east-1)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
