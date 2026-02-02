# Sao Paulo state vars
project_name = "liberdade"

# VPC CIDR for Sao Paulo
vpc_cidr = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.101.0/24", "10.1.102.0/24"]
azs = ["sa-east-1a", "sa-east-1c"]

ec2_instance_type = "t3.micro"

# Tokyo remote state (update if different)
tokyo_state_bucket = "shinjuku"
tokyo_state_key    = "tokyo/terraform.tfstate"
tokyo_state_region = "us-east-1"

# Peering attachment ID from Tokyo (set after Tokyo apply)
tokyo_tgw_peering_attachment_id = "tgw-attach-054235d8e2b012cdd"



# Disable remote state until S3 access is available
use_tokyo_remote_state = false

# Fallbacks when remote state is disabled
# Update these with real Tokyo values if needed
# tokyo_vpc_cidr = "10.0.0.0/16"
# tokyo_rds_endpoint = "REPLACE_ME"
# tokyo_rds_port = 3306

