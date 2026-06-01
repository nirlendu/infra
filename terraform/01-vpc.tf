###############################################################################
# 01 — SHARED VPC
#
# One VPC, one public subnet for app hosts, two private subnets for RDS
# (RDS subnet group needs 2 AZs even for single-AZ deploys).
#
# Every app stack reads vpc_id + public_subnet_id from SSM.
###############################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "shared-${var.env}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "shared-${var.env}-igw" }
}

# Public subnet — every app's EC2 host lands here. SGs handle isolation.
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false # apps attach their own EIP

  tags = { Name = "shared-${var.env}-public-a" }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_a_cidr
  availability_zone = var.availability_zone

  tags = { Name = "shared-${var.env}-private-a" }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_b_cidr
  # RDS subnet group requires 2 distinct AZs — pick the first AZ != primary.
  availability_zone = [for az in data.aws_availability_zones.available.names : az if az != var.availability_zone][0]

  tags = { Name = "shared-${var.env}-private-b" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "shared-${var.env}-public-rt" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

# ──────────────────────────────────────────────────────────────────────────────
# RDS security group. App stacks add their host SG to this SG's ingress.
# No ingress here — apps create their own aws_security_group_rule pointing at
# this SG's id (read from SSM).
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "shared-${var.env}-rds"
  description = "Shared Postgres - apps grant their host SG ingress to this SG."
  vpc_id      = aws_vpc.this.id

  egress {
    description = "Block all outbound - RDS never initiates."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["127.0.0.1/32"]
  }

  tags = { Name = "shared-${var.env}-rds-sg" }

  lifecycle {
    # App stacks add ingress rules to this SG. Don't let Terraform fight them.
    ignore_changes = [ingress]
  }
}
