###############################################################################
# 03 — PUBLISH SHARED OUTPUTS TO SSM PARAMETER STORE
#
# Every consumer app reads from /shared/<env>/* via data sources. This avoids
# tight remote-state coupling — apps don't need terraform_remote_state.
#
# Path convention:
#   /shared/<env>/vpc/id
#   /shared/<env>/vpc/public-subnet-id
#   /shared/<env>/rds/endpoint
#   /shared/<env>/rds/port
#   /shared/<env>/rds/sg-id
#   /shared/<env>/rds/master-user
#   /shared/<env>/rds/master-password   (SecureString)
#   /shared/<env>/sns/alerts-topic-arn
###############################################################################

resource "aws_ssm_parameter" "vpc_id" {
  name        = "/shared/${var.env}/vpc/id"
  description = "Shared VPC id. Read by every app stack."
  type        = "String"
  value       = aws_vpc.this.id
}

resource "aws_ssm_parameter" "public_subnet_id" {
  name        = "/shared/${var.env}/vpc/public-subnet-id"
  description = "Shared public subnet — every app's EC2 host lands here."
  type        = "String"
  value       = aws_subnet.public_a.id
}

resource "aws_ssm_parameter" "rds_endpoint" {
  name        = "/shared/${var.env}/rds/endpoint"
  description = "Shared Postgres endpoint (host)."
  type        = "String"
  value       = aws_db_instance.shared.address
}

resource "aws_ssm_parameter" "rds_port" {
  name        = "/shared/${var.env}/rds/port"
  description = "Shared Postgres port."
  type        = "String"
  value       = tostring(aws_db_instance.shared.port)
}

resource "aws_ssm_parameter" "rds_sg_id" {
  name        = "/shared/${var.env}/rds/sg-id"
  description = "Shared RDS security group id. App stacks add ingress rules to this SG."
  type        = "String"
  value       = aws_security_group.rds.id
}

resource "aws_ssm_parameter" "rds_master_user" {
  name        = "/shared/${var.env}/rds/master-user"
  description = "Shared Postgres master username. Apps need this to bootstrap their DB+role."
  type        = "String"
  value       = aws_db_instance.shared.username
}

resource "aws_ssm_parameter" "rds_master_password" {
  name        = "/shared/${var.env}/rds/master-password"
  description = "Shared Postgres master password. Apps read this on first boot to provision their DB+role."
  type        = "SecureString"
  value       = random_password.rds_master.result
  tier        = "Standard"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "alerts_topic" {
  name        = "/shared/${var.env}/sns/alerts-topic-arn"
  description = "SNS topic carrying budget/alarm notifications. Apps can wire their own alarms to this."
  type        = "String"
  value       = aws_sns_topic.budget_alerts.arn
}

resource "aws_ssm_parameter" "availability_zone" {
  name        = "/shared/${var.env}/vpc/availability-zone"
  description = "Primary AZ — apps must launch EBS volumes into this AZ."
  type        = "String"
  value       = var.availability_zone
}
