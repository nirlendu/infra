###############################################################################
# One cluster, one namespace and one log group per company.
###############################################################################

data "aws_ssm_parameter" "shared_vpc_id" {
  name = "/shared/${var.shared_env}/vpc/id"
}

locals {
  # `nonsensitive` because a VPC id is not a secret, and the provider marks every
  # SSM value sensitive — which would then spread to anything referencing it,
  # including outputs this stack exists to publish.
  vpc_id = nonsensitive(data.aws_ssm_parameter.shared_vpc_id.value)
}

resource "aws_ecs_cluster" "company" {
  for_each = var.companies

  name = "${each.key}-${var.env}"

  setting {
    # Container Insights is the ONE per-cluster billable setting, and it is
    # `disabled` on authoxi-prod and agitome-prod. Leaving it off is what keeps the
    # count of clusters a free decision — turn it on and cluster-per-company starts
    # billing per cluster.
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Company = each.key
    Env     = var.env
  }
}

resource "aws_ecs_cluster_capacity_providers" "company" {
  for_each = var.companies

  cluster_name       = aws_ecs_cluster.company[each.key].name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # Both providers are attached so a service can choose per-service; this only sets
  # what an unqualified deploy gets.
  default_capacity_provider_strategy {
    capacity_provider = each.value.prefer_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
    base              = 0
  }
}

# Private DNS, VPC-only. API Gateway's private integration resolves SRV records
# here, which is what lets a service run with no load balancer — and an ALB is both
# ~$16/mo and denied outright by the cost-guardrails IAM policy.
resource "aws_service_discovery_private_dns_namespace" "company" {
  for_each = var.companies

  name        = "${each.key}.internal"
  description = "${each.key} service discovery (private, VPC-only)."
  vpc         = local.vpc_id

  tags = {
    Company = each.key
  }
}

# One group per cluster; products write into it under their own stream prefix.
# Per-product groups would work too, but each new one is another place to forget
# a retention policy — and "never expires" is how log storage becomes a line item.
resource "aws_cloudwatch_log_group" "cluster" {
  for_each = var.companies

  name              = "/ecs/${each.key}-${var.env}"
  retention_in_days = each.value.log_retention_days

  tags = {
    Company = each.key
  }
}
