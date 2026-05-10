output "default_vpc_id" {
  description = "Default VPC ID where the shared RDS lives. Used by peer-VPC repos (e.g. Greenspace) when wiring same-account VPC peering."
  value       = data.aws_vpc.default.id
}

output "default_vpc_cidr" {
  description = "Default VPC CIDR block where the shared RDS lives. Used by peer-VPC repos when adding routes back to this VPC."
  value       = data.aws_vpc.default.cidr_block
}
