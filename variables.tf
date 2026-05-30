variable "aws_region" {
  type    = string
  default = "eu-north-1"
}

# Where the postgresql provider dials. RDS is private, so this is the local end
# of the SSM port-forward (see scripts/db-tunnel.sh and the CI workflow), not
# the RDS endpoint. Defaults match the documented tunnel; the local port is
# 15432 (not 5432) to avoid colliding with a Postgres running on the operator's
# laptop. Override only if you forward to a different local port.
variable "postgres_host" {
  type    = string
  default = "127.0.0.1"
}

variable "postgres_port" {
  type    = number
  default = 15432
}
