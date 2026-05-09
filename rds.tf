resource "random_password" "master" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "master" {
  name = "rds/shared/master"
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({
    host     = aws_db_instance.shared.address
    port     = aws_db_instance.shared.port
    database = aws_db_instance.shared.db_name
    username = aws_db_instance.shared.username
    password = random_password.master.result
  })
}

resource "aws_db_subnet_group" "shared" {
  name       = "shared-db"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "shared" {
  identifier = "shared-postgres"

  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 20
  storage_type          = "gp3"

  username = "tfadmin"
  password = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.shared.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = false
  publicly_accessible = true

  backup_retention_period   = 7
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "shared-postgres-final"
}
