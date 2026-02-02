variable "project_name" {
  description = "Prefix for naming (used in tags and resource names)."
  type        = string
  default     = "liberdade"
}

variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs."
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs."
  type        = list(string)
  default     = ["10.1.101.0/24", "10.1.102.0/24"]
}

variable "azs" {
  description = "Availability Zones list (match count with subnets)."
  type        = list(string)
  default     = ["sa-east-1a", "sa-east-1c"]
}

variable "ec2_instance_type" {
  description = "EC2 instance size for the app."
  type        = string
  default     = "t3.micro"
}

variable "tokyo_state_bucket" {
  description = "S3 bucket for Tokyo Terraform state."
  type        = string
  default     = "shinjuku"
}

variable "tokyo_state_key" {
  description = "S3 key for Tokyo Terraform state."
  type        = string
  default     = "tokyo/terraform.tfstate"
}

variable "tokyo_state_region" {
  description = "S3 region for Tokyo Terraform state."
  type        = string
  default     = "ap-northeast-1"
}

variable "tokyo_tgw_peering_attachment_id" {
  description = "Peering attachment ID from Tokyo TGW request."
  type        = string
  default     = null
  nullable    = true
}

variable "use_tokyo_remote_state" {
  description = "Whether to read Tokyo outputs from remote state (requires S3 access)."
  type        = bool
  default     = false
}

variable "tokyo_vpc_cidr" {
  description = "Tokyo VPC CIDR (fallback when remote state is disabled)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "tokyo_rds_endpoint" {
  description = "Tokyo RDS endpoint (fallback when remote state is disabled)."
  type        = string
  default     = "REPLACE_ME"
}

variable "tokyo_rds_port" {
  description = "Tokyo RDS port (fallback when remote state is disabled)."
  type        = number
  default     = 3306
}

variable "origin_header_name" {
  description = "Custom header name required by the ALB listener rule."
  type        = string
  default     = "X-Origin-Verify"
}

variable "origin_header_value" {
  description = "Custom header value required by the ALB listener rule."
  type        = string
  default     = "liberdade-origin"
}

variable "asg_min_size" {
  description = "Auto Scaling Group minimum size."
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Auto Scaling Group maximum size."
  type        = number
  default     = 2
}

variable "asg_desired_capacity" {
  description = "Auto Scaling Group desired capacity."
  type        = number
  default     = 1
}
