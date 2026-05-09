output "database_name" {
  value = postgresql_database.app.name
}

output "role_name" {
  value = postgresql_role.app.name
}

output "secret_arn" {
  value = aws_secretsmanager_secret.app.arn
}
