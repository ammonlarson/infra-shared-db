data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_route_table" "default_main" {
  vpc_id = data.aws_vpc.default.id

  filter {
    name   = "association.main"
    values = ["true"]
  }
}

resource "aws_security_group" "rds" {
  name        = "shared-db-rds"
  description = "Inbound Postgres for shared RDS"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Operator ingress lives in separate rule resources because the greenspace
# peering ingress (peering.tf) uses aws_vpc_security_group_ingress_rule, and
# the AWS provider treats inline ingress + per-rule resources on the same SG
# as a conflict.
resource "aws_vpc_security_group_ingress_rule" "operator" {
  for_each = toset(var.allowed_ingress_cidrs)

  security_group_id = aws_security_group.rds.id
  description       = "Postgres operator access"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = each.value
}
