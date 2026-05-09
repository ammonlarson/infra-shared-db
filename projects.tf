locals {
  projects = [
    "greenspace",
  ]
}

module "projects" {
  source   = "./modules/project"
  for_each = toset(local.projects)

  name    = each.key
  db_host = aws_db_instance.shared.address
  db_port = aws_db_instance.shared.port
}
