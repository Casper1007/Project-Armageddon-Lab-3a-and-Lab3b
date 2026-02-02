output "saopaulo_tgw_id" {
  description = "Sao Paulo Transit Gateway ID for cross-region peering"
  value       = aws_ec2_transit_gateway.liberdade_tgw01.id
}
