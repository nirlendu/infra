output "vpc_id" {
  description = "Shared VPC id. Also published at /shared/<env>/vpc/id in SSM."
  value       = aws_vpc.this.id
}

output "public_subnet_id" {
  description = "Public subnet id every app's EC2 host lands in."
  value       = aws_subnet.public_a.id
}

output "rds_endpoint" {
  description = "Shared Postgres endpoint."
  value       = aws_db_instance.shared.address
}

output "rds_sg_id" {
  description = "Shared RDS security group id. App stacks add ingress rules to this SG."
  value       = aws_security_group.rds.id
}

output "budget_alerts_topic_arn" {
  description = "SNS topic for shared budget/alarm notifications."
  value       = aws_sns_topic.budget_alerts.arn
}

output "ssm_paths" {
  description = "All published SSM paths app stacks should consume."
  value = {
    vpc_id              = aws_ssm_parameter.vpc_id.name
    public_subnet_id    = aws_ssm_parameter.public_subnet_id.name
    rds_endpoint        = aws_ssm_parameter.rds_endpoint.name
    rds_port            = aws_ssm_parameter.rds_port.name
    rds_sg_id           = aws_ssm_parameter.rds_sg_id.name
    rds_master_user     = aws_ssm_parameter.rds_master_user.name
    rds_master_password = aws_ssm_parameter.rds_master_password.name
    alerts_topic_arn    = aws_ssm_parameter.alerts_topic.name
    availability_zone   = aws_ssm_parameter.availability_zone.name
  }
}

output "cost_guardrails_policy_arn" {
  description = "Attach this managed IAM policy to your operator IAM user to physically block NAT Gateway / ALB / oversized instance creation."
  value       = aws_iam_policy.cost_guardrails.arn
}

output "cost_restricted_group_name" {
  description = "IAM group with cost_guardrails attached. `aws iam add-user-to-group --group-name <this> --user-name <you>` to opt in."
  value       = aws_iam_group.cost_restricted.name
}

output "first_apply_command" {
  description = "Apply this targeted set FIRST so EVERY tripwire is live before any billable resource spins up."
  value       = <<-EOT
    terraform apply \
      -target=aws_sns_topic.budget_alerts \
      -target=aws_sns_topic_subscription.budget_alerts_email \
      -target=aws_budgets_budget.monthly_cost \
      -target=aws_budgets_budget.daily_anomaly \
      -target=aws_budgets_budget.ec2 \
      -target=aws_budgets_budget.rds \
      -target=aws_budgets_budget.vpc \
      -target=aws_budgets_budget.elb \
      -target=aws_budgets_budget.data_transfer \
      -target=aws_cloudwatch_metric_alarm.billing \
      -target=aws_ce_anomaly_monitor.all_services \
      -target=aws_ce_anomaly_subscription.email \
      -target=aws_iam_policy.cost_guardrails \
      -target=aws_iam_group.cost_restricted \
      -target=aws_iam_group_policy_attachment.cost_restricted
  EOT
}
