###############################################################################
# APP NETWORK — host SG in the shared public subnet + ingress to shared RDS SG.
###############################################################################

resource "aws_security_group" "host" {
  name        = "${var.name_prefix}-${var.env}-host"
  description = "${var.name_prefix} EC2 host: 80/443 from world, optional SSH, egress anywhere"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTP (Caddy ACME challenge + redirect)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.ssh_cidr == "" ? [] : [var.ssh_cidr]
    content {
      description = "SSH (operator only)"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-${var.env}-host-sg" }
}

# Add our host SG to the shared RDS SG's ingress so this host can reach Postgres.
resource "aws_security_group_rule" "rds_from_host" {
  type                     = "ingress"
  security_group_id        = local.rds_sg_id
  source_security_group_id = aws_security_group.host.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  description              = "${var.name_prefix}-${var.env} host -> shared Postgres"
}
