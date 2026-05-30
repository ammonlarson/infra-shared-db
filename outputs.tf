output "default_vpc_id" {
  description = "Default VPC ID where the shared RDS lives. Used by peer-VPC repos (e.g. Greenspace) when wiring same-account VPC peering."
  value       = data.aws_vpc.default.id
}

output "default_vpc_cidr" {
  description = "Default VPC CIDR block where the shared RDS lives. Used by peer-VPC repos when adding routes back to this VPC."
  value       = data.aws_vpc.default.cidr_block
}

output "bastion_instance_id" {
  description = "Instance ID of the SSM bastion. Pass it to scripts/db-tunnel.sh or `aws ssm start-session` to reach the private RDS."
  value       = aws_instance.bastion.id
}

output "rds_endpoint" {
  description = "Private RDS endpoint address. The far-side host for the SSM port-forward (the bastion dials this on your behalf)."
  value       = aws_db_instance.shared.address
}

output "db_tunnel_command" {
  description = "Copy-paste SSM port-forward that maps localhost:5432 to the private RDS endpoint. Run it, then `terraform plan`/`apply` (or psql) against localhost."
  value       = "aws ssm start-session --target ${aws_instance.bastion.id} --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '{\"host\":[\"${aws_db_instance.shared.address}\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"5432\"]}' --region ${var.aws_region}"
}
