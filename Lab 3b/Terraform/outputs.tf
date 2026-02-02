##
# These outputs are required for cross-region remote state consumption by SÃ£o Paulo.
#
# - tokyo_vpc_cidr: Used for TGW routing in SÃ£o Paulo
# - tokyo_rds_endpoint: Used for app/database connectivity from SÃ£o Paulo
output "tokyo_vpc_cidr" {
  description = "Tokyo VPC CIDR for cross-region routing"
  value       = aws_vpc.chrisbarm_vpc01.cidr_block
}

output "tokyo_rds_endpoint" {
  description = "Tokyo RDS endpoint for remote access"
  value       = aws_db_instance.chrisbarm_rds01.address
}

output "tokyo_tgw_id" {
  description = "Tokyo Transit Gateway ID for cross-region peering"
  value       = aws_ec2_transit_gateway.shinjuku_tgw01.id
}

output "tokyo_tgw_peering_attachment_id" {
  description = "TGW peering attachment ID requested by Tokyo"
  value       = try(aws_ec2_transit_gateway_peering_attachment.shinjuku_to_liberdade_peer01[0].id, null)
}

