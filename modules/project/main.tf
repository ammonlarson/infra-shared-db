terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.22"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

resource "random_password" "app" {
  length  = 32
  special = false
}

resource "postgresql_role" "app" {
  name     = "${var.name}_app"
  login    = true
  password = random_password.app.result
}

resource "postgresql_database" "app" {
  name  = var.name
  owner = postgresql_role.app.name
}

resource "aws_secretsmanager_secret" "app" {
  name = "rds/shared/${var.name}"
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    host     = var.db_host
    port     = var.db_port
    database = postgresql_database.app.name
    username = postgresql_role.app.name
    password = random_password.app.result
  })
}
