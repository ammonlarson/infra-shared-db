locals {
  # Accepter-side configuration for VPC peering connections owned by the
  # Greenspace repo. Greenspace creates the peerings (auto_accept = true,
  # requester.allow_remote_vpc_dns_resolution = true) and tags each one with
  # the Name below; this repo discovers them by tag and configures the
  # accepter side: DNS resolution and a route. The matching SG ingress
  # entries live in the inline ingress block on aws_security_group.rds in
  # network.tf — kept inline (rather than separate
  # aws_vpc_security_group_ingress_rule resources) because mixing the two
  # forms on the same SG fights, and the cidr_blocks list already gives
  # us per-CIDR scoping at the AWS rule level.
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

  # Loppemarked follows the same accepter-side pattern as Greenspace: it owns
  # the requester side (auto_accept + requester DNS resolution) and tags each
  # peering with the Name below; this repo discovers them by tag and configures
  # the accepter side. Loppemarked's VPC CIDRs are distinct from Greenspace's
  # (10.2/10.3 vs 10.0/10.1) so the per-CIDR routes don't collide in the shared
  # default VPC's route table.
  loppemarked_peering = {
    staging = {
      peering_tag_name = "loppemarked-staging-2026-shared-db-peering"
      vpc_cidr         = "10.2.0.0/16"
    }
    prod = {
      peering_tag_name = "loppemarked-prod-2026-shared-db-peering"
      vpc_cidr         = "10.3.0.0/16"
    }
  }
}

data "aws_vpc_peering_connection" "greenspace" {
  for_each = local.greenspace_peering

  filter {
    name   = "tag:Name"
    values = [each.value.peering_tag_name]
  }

  filter {
    name   = "status-code"
    values = ["active"]
  }

  filter {
    name   = "accepter-vpc-info.vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# With accepter-side DNS resolution enabled, AWS resolves the RDS endpoint to
# its private IP for queries originating in the peered VPC, so Greenspace's
# Lambdas reach RDS over the peering link rather than trying to leave via the
# (non-existent) NAT path.
resource "aws_vpc_peering_connection_options" "greenspace" {
  for_each = local.greenspace_peering

  vpc_peering_connection_id = data.aws_vpc_peering_connection.greenspace[each.key].id

  accepter {
    allow_remote_vpc_dns_resolution = true
  }
}

resource "aws_route" "greenspace" {
  for_each = local.greenspace_peering

  route_table_id            = data.aws_route_table.default_main.id
  destination_cidr_block    = each.value.vpc_cidr
  vpc_peering_connection_id = data.aws_vpc_peering_connection.greenspace[each.key].id
}

data "aws_vpc_peering_connection" "loppemarked" {
  for_each = local.loppemarked_peering

  filter {
    name   = "tag:Name"
    values = [each.value.peering_tag_name]
  }

  filter {
    name   = "status-code"
    values = ["active"]
  }

  filter {
    name   = "accepter-vpc-info.vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_vpc_peering_connection_options" "loppemarked" {
  for_each = local.loppemarked_peering

  vpc_peering_connection_id = data.aws_vpc_peering_connection.loppemarked[each.key].id

  accepter {
    allow_remote_vpc_dns_resolution = true
  }
}

resource "aws_route" "loppemarked" {
  for_each = local.loppemarked_peering

  route_table_id            = data.aws_route_table.default_main.id
  destination_cidr_block    = each.value.vpc_cidr
  vpc_peering_connection_id = data.aws_vpc_peering_connection.loppemarked[each.key].id
}
