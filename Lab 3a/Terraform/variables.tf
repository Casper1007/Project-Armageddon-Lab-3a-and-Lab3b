variable "aws_region" {
  description = "AWS Region for the Chrisbarm lab environment."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for naming (used in tags and resource names)."
  type        = string
  default     = "chrisbarm"
}


variable "vpc_cidr" {
  description = "VPC CIDR (use 10.0.0.0/16 as instructed)."
  type        = string
  default     = "10.0.0.0/16" # TODO: student supplies
  validation {
    condition     = can(regex("^10\\.\\d{1,3}\\.\\d{1,3}\\.0/\\d{1,2}$", var.vpc_cidr))
    error_message = "VPC CIDR must be a valid 10.x.x.0/xx CIDR block."
  }
}


variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (use 10.0.0.0/16)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"] # TODO: student supplies
  validation {
    condition     = alltrue([for cidr in var.public_subnet_cidrs : can(regex("^10\\.\\d{1,3}\\.\\d{1,3}\\.0/\\d{1,2}$", cidr))])
    error_message = "Each public subnet CIDR must be a valid 10.x.x.0/xx CIDR block."
  }
}


variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (use 10.0.0.0/16)."
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"] # TODO: student supplies
  validation {
    condition     = alltrue([for cidr in var.private_subnet_cidrs : can(regex("^10\\.\\d{1,3}\\.\\d{1,3}\\.0/\\d{1,2}$", cidr))])
    error_message = "Each private subnet CIDR must be a valid 10.x.x.0/xx CIDR block."
  }
}

variable "azs" {
  description = "Availability Zones list (match count with subnets)."
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "ec2_ami_id" {
  description = "AMI ID for the EC2 app host."
  type        = string
  default     = "ami-0ffd97eb6de3f647d" # Amazon Linux 2 for ap-northeast-1
}

variable "ec2_instance_type" {
  description = "EC2 instance size for the app."
  type        = string
  default     = "t3.micro"
}


variable "key_name" {
  description = "Optional EC2 key pair name. Leave null/empty to avoid SSH keys (SSM recommended)."
  type        = string
  default     = null
}
variable "db_engine" {
  description = "RDS engine."
  type        = string
  default     = "mysql"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}


variable "storage_type" {
  description = "RDS storage type (gp3 recommended)."
  type        = string
  default     = "gp3"
}
variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "labdb" # Students can change
}

variable "db_username" {
  description = "DB master username (students should use Secrets Manager in 1B/1C)."
  type        = string
  default     = "admin" # TODO: student supplies
}

variable "db_password" {
  description = "DB master password (DO NOT hardcode in real life; for lab only)."
  type        = string
  sensitive   = true
  default     = "REPLACE_ME" # TODO: student supplies
}

variable "sns_email_endpoint" {
  description = "Email for SNS subscription (PagerDuty simulation)."
  type        = string
  default     = "student@example.com" # TODO: student supplies
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the public domain."
  type        = string
  default     = "REPLACE_ME"
}

variable "domain_name" {
  description = "Apex domain name for CloudFront (e.g., chewbacca-growl.com)."
  type        = string
  default     = "chrisbdevsecops.com"
}

variable "app_subdomain" {
  description = "Subdomain for the app (e.g., app)."
  type        = string
  default     = "app"
}

variable "saopaulo_vpc_cidr" {
  description = "Sao Paulo VPC CIDR for TGW routing and RDS SG allowlist."
  type        = string
  default     = "10.1.0.0/16"
}






variable "saopaulo_tgw_id" {
  description = "Sao Paulo Transit Gateway ID for peering (from Sao Paulo state output)."
  type        = string
  default     = null
  nullable    = true
}
