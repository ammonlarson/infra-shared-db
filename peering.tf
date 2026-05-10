locals {
  # Accepter-side configuration for VPC peering connections owned by the
  # Greenspace repo. Greenspace creates the peerings (auto_accept = true,
  # requester.allow_remote_vpc_dns_resolution = true) and tags each one with
  # the Name below; this repo discovers them by tag and configures the
  # accepter side: DNS resolution, route, and SG ingress.
  greenspace_peering = {
    staging = {
      peering_tag_name = "greenspace-staging-2026-shared-db-peering"
      vpc_cidr         = "10.0.0.0/16"
    }
    prod = {
      peering_tag_name = "greenspace-prod-2026-shared-db-peering"
      vpc_cidr         = "10.1.0.0/16"
    }
  }
}

data "aws_vpc_peering_connection" "greenspace" {
  for_each = local.greenspace_peering

  filter {
    name   = "tag:Name"
    values = [each.value.peering_tag_name]
  }
}

# Without accepter-side DNS resolution the public RDS endpoint resolves to
# its public IP from the Greenspace VPC, which would then try to leave via
# the (non-existent) NAT path. With this enabled, AWS resolves the endpoint
# to the RDS private IP for queries originating in the peered VPC.
resource "aws_vpc_peering_connection_options" "greenspace" {
  for_each = local.greenspace_peering

  vpc_peering_connection_id = data.aws_vpc_peering_connection.greenspace[each.key].id

  accepter {
    allow_remote_vpc_dns_resolution = true
  }
}

resource "aws_route" "greenspace_peering" {
  for_each = local.greenspace_peering

  route_table_id            = data.aws_route_table.default_main.id
  destination_cidr_block    = each.value.vpc_cidr
  vpc_peering_connection_id = data.aws_vpc_peering_connection.greenspace[each.key].id
}

resource "aws_vpc_security_group_ingress_rule" "greenspace" {
  for_each = local.greenspace_peering

  security_group_id = aws_security_group.rds.id
  description       = "Postgres from greenspace ${each.key} VPC"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = each.value.vpc_cidr
}
