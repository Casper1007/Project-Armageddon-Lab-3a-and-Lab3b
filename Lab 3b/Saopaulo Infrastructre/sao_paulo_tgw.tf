# Liberdade TGW (Sao Paulo region)
resource "aws_ec2_transit_gateway" "liberdade_tgw01" {
  description = "liberdade-tgw01 (Sao Paulo spoke)"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  tags        = { Name = "liberdade-tgw01" }
}

resource "aws_ec2_transit_gateway_route_table" "liberdade_tgw_rt01" {
  transit_gateway_id = aws_ec2_transit_gateway.liberdade_tgw01.id
  tags               = { Name = "liberdade-tgw-rt01" }
}

# Accept the corridor from Shinjuku
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "liberdade_accept_peer01" {
  count                         = var.tokyo_tgw_peering_attachment_id == null ? 0 : 1
  transit_gateway_attachment_id = var.tokyo_tgw_peering_attachment_id
  tags                          = { Name = "liberdade-accept-peer01" }
}

# Attach Liberdade VPC to its TGW
resource "aws_ec2_transit_gateway_vpc_attachment" "liberdade_vpc_attachment01" {
  subnet_ids         = aws_subnet.liberdade_private_subnets[*].id
  transit_gateway_id = aws_ec2_transit_gateway.liberdade_tgw01.id
  vpc_id             = aws_vpc.liberdade_vpc01.id
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  tags               = { Name = "liberdade-vpc-attachment01" }
}

resource "aws_ec2_transit_gateway_route_table_association" "liberdade_vpc_assoc01" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.liberdade_vpc_attachment01.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.liberdade_tgw_rt01.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "liberdade_vpc_prop01" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.liberdade_vpc_attachment01.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.liberdade_tgw_rt01.id
}

# Note: Peering attachments cannot be associated with route tables in São Paulo either
# AWS requires static routes only for cross-region peering

resource "aws_ec2_transit_gateway_route" "liberdade_to_shinjuku_tgw_route01" {
  count                          = var.tokyo_tgw_peering_attachment_id == null ? 0 : 1
  destination_cidr_block         = local.tokyo_vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.liberdade_accept_peer01[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.liberdade_tgw_rt01.id
  depends_on                     = [aws_ec2_transit_gateway_peering_attachment_accepter.liberdade_accept_peer01]
}
