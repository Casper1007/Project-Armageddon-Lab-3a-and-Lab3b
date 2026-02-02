# Explanation: Tokyoâ€™s vault opens only to approved clinicsâ€”Liberdade gets DB access, the public gets nothing.
resource "aws_security_group_rule" "shinjuku_rds_ingress_from_liberdade01" {
  type              = "ingress"
  security_group_id = aws_security_group.chrisbarm_rds_sg01.id
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"

  cidr_blocks = [var.saopaulo_vpc_cidr] # Sao Paulo VPC CIDR (example)
}
