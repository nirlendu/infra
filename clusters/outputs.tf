output "clusters" {
  description = "Cluster name per company."
  value       = { for k, c in aws_ecs_cluster.company : k => c.name }
}

output "namespaces" {
  description = "Cloud Map namespace per company. Products register a service inside these."
  value       = { for k, n in aws_service_discovery_private_dns_namespace.company : k => n.name }
}

output "log_groups" {
  description = "Shared log group per company."
  value       = { for k, g in aws_cloudwatch_log_group.cluster : k => g.name }
}

output "published_parameters" {
  description = "What product stacks read. Adding a company adds one set of these."
  value = flatten([
    for k in keys(var.companies) : [
      "/${k}/${var.env}/ecs/cluster-name",
      "/${k}/${var.env}/ecs/cluster-arn",
      "/${k}/${var.env}/ecs/namespace-id",
      "/${k}/${var.env}/ecs/log-group-name",
    ]
  ])
}
