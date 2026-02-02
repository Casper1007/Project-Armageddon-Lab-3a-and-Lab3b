############################################
# Locals (naming convention: liberdade-*)
############################################
locals {
  name_prefix = var.project_name
  ports_http  = 80
  ports_ssh   = 22
  ports_https = 443
  db_port     = 3306
  tcp_protocol = "tcp"
  all_ip_address = "0.0.0.0/0"
  all_ports    = 0
  all_protocol = "-1"
}

############################################
# VPC + Internet Gateway
############################################
resource "aws_vpc" "liberdade_vpc01" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc01"
  }
}

resource "aws_internet_gateway" "liberdade_igw01" {
  vpc_id = aws_vpc.liberdade_vpc01.id

  tags = {
    Name = "${local.name_prefix}-igw01"
  }
}

############################################
# Subnets (Public + Private)
############################################
resource "aws_subnet" "liberdade_public_subnets" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.liberdade_vpc01.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-subnet0${count.index + 1}"
  }
}

resource "aws_subnet" "liberdade_private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.liberdade_vpc01.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${local.name_prefix}-private-subnet0${count.index + 1}"
  }
}

############################################
# NAT Gateway + EIP
############################################
resource "aws_eip" "liberdade_nat_eip01" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip01"
  }
}

resource "aws_nat_gateway" "liberdade_nat01" {
  allocation_id = aws_eip.liberdade_nat_eip01.id
  subnet_id     = aws_subnet.liberdade_public_subnets[0].id

  tags = {
    Name = "${local.name_prefix}-nat01"
  }

  depends_on = [aws_internet_gateway.liberdade_igw01]
}

############################################
# Routing (Public + Private Route Tables)
############################################
resource "aws_route_table" "liberdade_public_rt01" {
  vpc_id = aws_vpc.liberdade_vpc01.id

  tags = {
    Name = "${local.name_prefix}-public-rt01"
  }
}

resource "aws_route" "liberdade_public_default_route" {
  route_table_id         = aws_route_table.liberdade_public_rt01.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.liberdade_igw01.id
}

resource "aws_route_table_association" "liberdade_public_rta" {
  count          = length(aws_subnet.liberdade_public_subnets)
  subnet_id      = aws_subnet.liberdade_public_subnets[count.index].id
  route_table_id = aws_route_table.liberdade_public_rt01.id
}

resource "aws_route_table" "liberdade_private_rt01" {
  vpc_id = aws_vpc.liberdade_vpc01.id

  tags = {
    Name = "${local.name_prefix}-private-rt01"
  }
}

resource "aws_route" "liberdade_private_default_route" {
  route_table_id         = aws_route_table.liberdade_private_rt01.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.liberdade_nat01.id
}

resource "aws_route_table_association" "liberdade_private_rta" {
  count          = length(aws_subnet.liberdade_private_subnets)
  subnet_id      = aws_subnet.liberdade_private_subnets[count.index].id
  route_table_id = aws_route_table.liberdade_private_rt01.id
}

############################################
# Security Groups (EC2)
############################################
resource "aws_security_group" "liberdade_ec2_sg01" {
  name        = "${local.name_prefix}-ec2-sg01"
  description = "EC2 app security group"
  vpc_id      = aws_vpc.liberdade_vpc01.id

  tags = {
    Name = "${local.name_prefix}-ec2-sg01"
  }
}

resource "aws_vpc_security_group_ingress_rule" "liberdade_ec2_sg_ingress_http" {
  ip_protocol       = local.tcp_protocol
  security_group_id = aws_security_group.liberdade_ec2_sg01.id
  from_port         = local.ports_http
  to_port           = local.ports_http
  cidr_ipv4         = local.all_ip_address
}

resource "aws_vpc_security_group_egress_rule" "liberdade_ec2_sg_egress_all" {
  ip_protocol       = local.all_protocol
  security_group_id = aws_security_group.liberdade_ec2_sg01.id
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = local.all_ip_address
}

resource "aws_security_group" "liberdade_alb_sg01" {
  name        = "${local.name_prefix}-alb-sg01"
  description = "ALB security group"
  vpc_id      = aws_vpc.liberdade_vpc01.id

  tags = {
    Name = "${local.name_prefix}-alb-sg01"
  }
}

resource "aws_vpc_security_group_ingress_rule" "liberdade_alb_sg_ingress_http" {
  ip_protocol       = local.tcp_protocol
  security_group_id = aws_security_group.liberdade_alb_sg01.id
  from_port         = local.ports_http
  to_port           = local.ports_http
  cidr_ipv4         = local.all_ip_address
}

resource "aws_vpc_security_group_egress_rule" "liberdade_alb_sg_egress_all" {
  ip_protocol       = local.all_protocol
  security_group_id = aws_security_group.liberdade_alb_sg01.id
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = local.all_ip_address
}

resource "aws_security_group" "liberdade_asg_sg01" {
  name        = "${local.name_prefix}-asg-sg01"
  description = "ASG instance security group"
  vpc_id      = aws_vpc.liberdade_vpc01.id

  tags = {
    Name = "${local.name_prefix}-asg-sg01"
  }
}

resource "aws_vpc_security_group_ingress_rule" "liberdade_asg_sg_ingress_http_from_alb" {
  ip_protocol                  = local.tcp_protocol
  security_group_id            = aws_security_group.liberdade_asg_sg01.id
  from_port                    = local.ports_http
  to_port                      = local.ports_http
  referenced_security_group_id = aws_security_group.liberdade_alb_sg01.id
}

resource "aws_vpc_security_group_egress_rule" "liberdade_asg_sg_egress_all" {
  ip_protocol       = local.all_protocol
  security_group_id = aws_security_group.liberdade_asg_sg01.id
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = local.all_ip_address
}

############################################
# EC2 Instance (App Host)
############################################
data "aws_ami" "al2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "liberdade_ec2_01" {
  ami                         = data.aws_ami.al2.id
  instance_type               = var.ec2_instance_type
  subnet_id                   = aws_subnet.liberdade_private_subnets[0].id
  vpc_security_group_ids      = [aws_security_group.liberdade_ec2_sg01.id]
  associate_public_ip_address = false

  tags = {
    Name = "${local.name_prefix}-ec2-01"
  }
}

############################################
# ALB + Target Group + Listener (Origin Header Rule)
############################################
resource "aws_lb" "liberdade_alb01" {
  name               = "${local.name_prefix}-alb01"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.liberdade_alb_sg01.id]
  subnets            = aws_subnet.liberdade_public_subnets[*].id

  tags = {
    Name = "${local.name_prefix}-alb01"
  }
}

resource "aws_lb_target_group" "liberdade_tg01" {
  name     = "${local.name_prefix}-tg01"
  port     = local.ports_http
  protocol = "HTTP"
  vpc_id   = aws_vpc.liberdade_vpc01.id

  health_check {
    protocol = "HTTP"
    path     = "/"
  }

  tags = {
    Name = "${local.name_prefix}-tg01"
  }
}

resource "aws_lb_listener" "liberdade_alb_listener_http" {
  load_balancer_arn = aws_lb.liberdade_alb01.arn
  port              = local.ports_http
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}

resource "aws_lb_listener_rule" "liberdade_alb_origin_header_rule" {
  listener_arn = aws_lb_listener.liberdade_alb_listener_http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.liberdade_tg01.arn
  }

  condition {
    http_header {
      http_header_name = var.origin_header_name
      values           = [var.origin_header_value]
    }
  }
}

############################################
# Launch Template + Auto Scaling Group
############################################
resource "aws_launch_template" "liberdade_lt01" {
  name_prefix   = "${local.name_prefix}-lt01-"
  image_id      = data.aws_ami.al2.id
  instance_type = var.ec2_instance_type

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.liberdade_asg_sg01.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name_prefix}-asg-ec2"
    }
  }
}

resource "aws_autoscaling_group" "liberdade_asg01" {
  name                      = "${local.name_prefix}-asg01"
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  vpc_zone_identifier       = aws_subnet.liberdade_private_subnets[*].id
  health_check_type         = "ELB"
  health_check_grace_period = 120
  target_group_arns         = [aws_lb_target_group.liberdade_tg01.arn]

  launch_template {
    id      = aws_launch_template.liberdade_lt01.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-asg01"
    propagate_at_launch = true
  }
}

############################################
# CloudFront Distribution (Origin Header)
############################################
resource "aws_cloudfront_distribution" "liberdade_cf01" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Liberdade CloudFront distribution"
  default_root_object = ""

  # ============================================================================
  # AUDIT EVIDENCE — Edge Access Logging
  # ============================================================================
  logging_config {
    include_cookies = false
    bucket          = "chrisbarm-cloudfront-logs-${data.aws_caller_identity.saopaulo_current.account_id}.s3.amazonaws.com"
    prefix          = "saopaulo-cf/"
  }

  # ============================================================================
  # AUDIT EVIDENCE — WAF Security Protection
  # ============================================================================
  web_acl_id = aws_wafv2_web_acl.liberdade_waf_acl.arn

  origin {
    domain_name = aws_lb.liberdade_alb01.dns_name
    origin_id   = "${local.name_prefix}-alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = var.origin_header_name
      value = var.origin_header_value
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "${local.name_prefix}-alb-origin"

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${local.name_prefix}-cf01"
  }
}

############################################
# Parameter Store (optional copies)
############################################
resource "aws_ssm_parameter" "liberdade_db_endpoint_param" {
  name      = "/lab/db/endpoint"
  type      = "String"
  value     = local.tokyo_rds_endpoint
  overwrite = true

  tags = {
    Name = "${local.name_prefix}-param-db-endpoint"
  }
}

resource "aws_ssm_parameter" "liberdade_db_port_param" {
  name      = "/lab/db/port"
  type      = "String"
  value     = tostring(local.tokyo_rds_port)
  overwrite = true

  tags = {
    Name = "${local.name_prefix}-param-db-port"
  }
}
