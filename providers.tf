provider "aws" {
  region = var.aws_region
}

provider "postgresql" {
  host      = aws_db_instance.shared.address
  port      = aws_db_instance.shared.port
  username  = aws_db_instance.shared.username
  password  = random_password.master.result
  sslmode   = "require"
  superuser = false
}
