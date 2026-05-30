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

  # RDS is private (publicly_accessible = false). The only operator/CI path in
  # is the SSM bastion, which reaches Postgres from inside the VPC, so ingress
  # is the bastion's SG rather than any allowlisted IP.
  ingress {
    description     = "Postgres from SSM bastion"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # AWS treats each entry in cidr_blocks as a separate ingress rule on the SG,
  # so revoking just the staging CIDR is a one-line config edit and a single
  # API call — the prod CIDR stays in place. These are the Greenspace peered
  # VPCs whose Lambdas reach RDS over the peering link, not over the internet.
  ingress {
    description = "Postgres from peered Greenspace VPCs"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [for v in local.greenspace_peering : v.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
