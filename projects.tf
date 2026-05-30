locals {
  # Projects with multiple deployment environments use a `<project>_<env>`
  # suffix so each environment gets its own database, role, and secret.
  projects = [
    "greenspace_staging",
    "greenspace_prod",
    "loppemarked_staging",
    "loppemarked_prod",
  ]
}

module "projects" {
  source   = "./modules/project"
  for_each = toset(local.projects)

  name    = each.key
  db_host = aws_db_instance.shared.address
  db_port = aws_db_instance.shared.port
}
