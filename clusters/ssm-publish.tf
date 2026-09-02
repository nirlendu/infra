###############################################################################
# The discovery contract.
#
# Product stacks read these rather than using `terraform_remote_state`, for the
# same reason ../terraform publishes /shared/<env>/* : a remote-state read couples
# the consumer to this stack's internal layout and needs read access to its state
# file, which also contains everything else this stack knows.
#
# A parameter is a narrower promise. Rename a resource here and consumers do not
# care; change a VALUE and they pick it up on their next apply.
###############################################################################

resource "aws_ssm_parameter" "cluster_name" {
  for_each = var.companies

  name        = "/${each.key}/${var.env}/ecs/cluster-name"
  description = "The ${each.key} ECS cluster. Products JOIN this; they do not create their own."
  type        = "String"
  value       = aws_ecs_cluster.company[each.key].name
}

resource "aws_ssm_parameter" "cluster_arn" {
  for_each = var.companies

  name        = "/${each.key}/${var.env}/ecs/cluster-arn"
  description = "ARN form, for IAM conditions and `aws ecs` calls that want it."
  type        = "String"
  value       = aws_ecs_cluster.company[each.key].arn
}

resource "aws_ssm_parameter" "namespace_id" {
  for_each = var.companies

  name        = "/${each.key}/${var.env}/ecs/namespace-id"
  description = "Cloud Map namespace shared by ${each.key} products. Each product registers its own SERVICE inside it."
  type        = "String"
  value       = aws_service_discovery_private_dns_namespace.company[each.key].id
}

resource "aws_ssm_parameter" "log_group_name" {
  for_each = var.companies

  name        = "/${each.key}/${var.env}/ecs/log-group-name"
  description = "Shared log group. Products write under their own awslogs-stream-prefix."
  type        = "String"
  value       = aws_cloudwatch_log_group.cluster[each.key].name
}
