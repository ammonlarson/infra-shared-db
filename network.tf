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

  # AWS treats each entry in cidr_blocks as a separate ingress rule on the
  # SG, so revoking just the staging CIDR is a one-line config edit and a
  # single API call — the prod CIDR and operator CIDRs stay in place.
  ingress {
    description = "Postgres"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = concat(
      var.allowed_ingress_cidrs,
      [for v in local.greenspace_peering : v.vpc_cidr],
    )
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
