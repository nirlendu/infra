output "instance_id" {
  description = "EC2 instance ID. Use with: aws ssm start-session --target <id>"
  value       = aws_instance.host.id
}

output "public_ip" {
  description = "Elastic IP attached to the host. Point DNS A records here."
  value       = aws_eip.host.public_ip
}

output "ssm_session_command" {
  description = "Open an interactive shell on the host without SSH."
  value       = "aws ssm start-session --region ${data.aws_region.current.name} --target ${aws_instance.host.id}"
}

output "backup_bucket" {
  description = "S3 bucket the host ships backups to."
  value       = aws_s3_bucket.backups.id
}

output "host_security_group_id" {
  description = "Host SG id."
  value       = aws_security_group.host.id
}

output "shared_rds_endpoint" {
  description = "Shared RDS endpoint this app connects to."
  value       = local.rds_endpoint
}

output "app_db_name" {
  description = "Postgres database this app uses on the shared RDS instance."
  value       = aws_ssm_parameter.app_db_name.value
}

output "app_db_user" {
  description = "Postgres role this app connects as."
  value       = aws_ssm_parameter.app_db_user.value
}
