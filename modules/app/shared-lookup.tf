###############################################################################
# SHARED-INFRA LOOKUPS
#
# Every value here is published by personal/infra/terraform/ under /shared/<env>/.
# We use SSM data sources rather than terraform_remote_state so the stacks don't
# share state files.
###############################################################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "shared_vpc_id" {
  name = "/shared/${var.shared_env}/vpc/id"
}

data "aws_ssm_parameter" "shared_public_subnet_id" {
  name = "/shared/${var.shared_env}/vpc/public-subnet-id"
}

data "aws_ssm_parameter" "shared_availability_zone" {
  name = "/shared/${var.shared_env}/vpc/availability-zone"
}

data "aws_ssm_parameter" "shared_rds_endpoint" {
  name = "/shared/${var.shared_env}/rds/endpoint"
}

data "aws_ssm_parameter" "shared_rds_port" {
  name = "/shared/${var.shared_env}/rds/port"
}

data "aws_ssm_parameter" "shared_rds_sg_id" {
  name = "/shared/${var.shared_env}/rds/sg-id"
}

data "aws_ssm_parameter" "shared_rds_master_user" {
  name = "/shared/${var.shared_env}/rds/master-user"
}

data "aws_ssm_parameter" "shared_alerts_topic" {
  name = "/shared/${var.shared_env}/sns/alerts-topic-arn"
}

locals {
  vpc_id              = data.aws_ssm_parameter.shared_vpc_id.value
  public_subnet_id    = data.aws_ssm_parameter.shared_public_subnet_id.value
  availability_zone   = data.aws_ssm_parameter.shared_availability_zone.value
  rds_endpoint        = data.aws_ssm_parameter.shared_rds_endpoint.value
  rds_port            = data.aws_ssm_parameter.shared_rds_port.value
  rds_sg_id           = data.aws_ssm_parameter.shared_rds_sg_id.value
  rds_master_user     = data.aws_ssm_parameter.shared_rds_master_user.value
  shared_alerts_topic = data.aws_ssm_parameter.shared_alerts_topic.value

  data_mount = var.data_mount != "" ? var.data_mount : "/var/lib/${var.name_prefix}"
}
