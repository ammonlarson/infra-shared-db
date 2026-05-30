provider "aws" {
  region = var.aws_region
}

# RDS is private, so the provider connects through the SSM port-forward rather
# than to the RDS endpoint directly. Defaults match the documented tunnel
# (scripts/db-tunnel.sh / the CI workflow): localhost on 5432. sslmode=require
# still applies — RDS terminates TLS at the far end of the tunnel; the local
# host name is not certificate-verified.
provider "postgresql" {
  host      = var.postgres_host
  port      = var.postgres_port
  username  = aws_db_instance.shared.username
  password  = random_password.master.result
  sslmode   = "require"
  superuser = false
}
