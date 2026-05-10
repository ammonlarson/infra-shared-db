# Ticket 21: Accepter-side same-account VPC peering for Greenspace

## Analysis

**Current state**

- `network.tf` defines the default-VPC discovery (`data.aws_vpc.default`,
  `data.aws_subnets.default`) and `aws_security_group.rds` with one inline
  `ingress` block sourced from `var.allowed_ingress_cidrs` (operator `/32`s
  only) and an open `egress`. The shared RDS instance lives in this VPC and
  is `publicly_accessible = true`.
- There are no peering, route, or peering-options resources today. There is
  also no data source for the default route table.
- Greenspace owns the **requester** side of two peering connections
  (`greenspace-staging-2026-shared-db-peering`,
  `greenspace-prod-2026-shared-db-peering`), created with `auto_accept = true`
  and `requester.allow_remote_vpc_dns_resolution = true`. The peering
  connections are created on the Greenspace operator's apply, before this
  repo's apply.

**Target state**

This repo owns the **accepter** side:

1. Discover both peering connections via `data "aws_vpc_peering_connection"`
   filtered by the Greenspace `Name` tag.
2. `aws_vpc_peering_connection_options` per peering with
   `accepter.allow_remote_vpc_dns_resolution = true` so the public RDS
   endpoint resolves to a private IP from inside the Greenspace VPC.
3. A route per peering in the default VPC's main route table sending the
   matching Greenspace VPC CIDR via the peering connection.
4. A per-environment ingress rule on the shared RDS security group
   permitting `tcp/5432` from the Greenspace VPC CIDR. CIDR-based — the
   ticket explicitly allows it ("use SG references if available, otherwise
   CIDR — both VPCs are same-account so SG-cross-VPC works once peered")
   and the Greenspace lambda SG isn't discoverable from this repo.

**Approach**

- New file `peering.tf`: a `local.greenspace_peering` map keyed by
  environment (`staging`, `prod`), holding the peering tag name and the VPC
  CIDR. All four resource sets (`data.aws_vpc_peering_connection`,
  `aws_vpc_peering_connection_options`, `aws_route`, and the new ingress
  rules) are `for_each = local.greenspace_peering`. Adding a third
  environment becomes a one-line edit, matching the project-list ergonomics
  in `projects.tf`.
- `network.tf`: add a `data "aws_route_table" "default_main"` filtered on
  `association.main = "true"`. Refactor `aws_security_group.rds` to drop
  its inline `ingress` block; replace with
  `aws_vpc_security_group_ingress_rule.operator` (one per operator CIDR via
  `for_each = toset(var.allowed_ingress_cidrs)`). Egress stays inline —
  `aws_vpc_security_group_ingress_rule` only conflicts with inline ingress,
  not inline egress, and there's no need to refactor egress.
- The refactor is required because the AWS provider docs warn that mixing
  `aws_vpc_security_group_ingress_rule` with inline `ingress` blocks on the
  same SG causes Terraform to fight on every plan. We need separate ingress
  resources to scope greenspace ingress per environment, so all ingress
  must move out of inline.
- Apply-time blast radius: during the one-time migration apply, the
  inline operator ingress is revoked and immediately re-authorized as a
  separate rule. There is a brief (single-API-call) window where the
  operator's CIDR is not on the SG. This PR doesn't touch any
  `postgresql_*` resources, so no postgres-provider operations run during
  the apply, which limits the blast radius to the operator's own session.
  Documented in the PR body.
- IAM policy (`policies/gha-terraform-shared-db.json`) does NOT need
  updating: CI runs only `init` + `validate`, neither of which calls EC2
  routing or peering APIs. The new EC2 calls
  (`DescribeVpcPeeringConnections`, `ModifyVpcPeeringConnectionOptions`,
  `DescribeRouteTables`, `CreateRoute`, etc.) happen on the operator's
  apply with the operator's own creds.

**Why no feature flag**

The data sources for the peering connections fail to plan if the peering
doesn't exist. Per the ticket sequencing, the operator must apply
Greenspace's PR #344 first (which creates the peering), then merge and
apply this PR. A feature flag (`enable_greenspace_peering = false` default)
would let the PR merge before Greenspace applies without breaking
operator-side `terraform plan` for unrelated changes, but it adds `count`
plumbing across every resource and contradicts the AC's framing ("are
discoverable... after Greenspace sets `shared_db_vpc_id` and applies").
Going without a flag; sequencing is documented in the PR body.

**README updates**

- Add a "Greenspace VPC peering (accepter side)" subsection under
  Architecture or after "Per-environment projects", explaining that this
  repo owns the accepter side, why DNS resolution is enabled, and the
  operator sequencing requirement.
- Update the `terraform.tfvars` rotation example: the diff for an operator
  IP change is now an `aws_vpc_security_group_ingress_rule` create/destroy,
  not a `~ ingress` on the SG. Adjust the wording in the Operator IP
  section.

## Task Checklist

- [x] Read ticket; add labels (`agent active`, `claude`).
- [x] Create planning document.
- [x] Create branch `claude/ticket-21-task-kBFD1` (already exists).
- [ ] Add `data "aws_route_table" "default_main"` to `network.tf`.
- [ ] Refactor `aws_security_group.rds` to remove inline ingress; add
      `aws_vpc_security_group_ingress_rule.operator` (`for_each` over
      `var.allowed_ingress_cidrs`).
- [ ] Create `peering.tf` with locals, data source, options, route, and
      greenspace ingress rule (all `for_each = local.greenspace_peering`).
- [ ] Update README: peering accepter subsection + adjust operator IP
      rotation diff description.
- [ ] Run `terraform fmt -check -recursive`.
- [ ] Run `terraform init -backend=false` + `terraform validate` (skip
      backend init — operator AWS creds aren't available in this session).
- [ ] Commit on `claude/ticket-21-task-kBFD1`; push.
- [ ] Open PR with sequencing notes and apply blast-radius warning.
- [ ] Run pr-reviewer agent, address feedback.
- [ ] Add `ammonl` reviewer; comment ticket; remove `agent active`.

## Implementation Summary

- Files touched:
  - `network.tf` — add route table data source, refactor SG ingress.
  - `peering.tf` — new file.
  - `README.md` — docs for peering accepter + IP rotation diff note.
- No changes to `modules/project/`, `projects.tf`, `rds.tf`,
  `providers.tf`, `versions.tf`, `variables.tf`, IAM policies, or CI.
- Estimated impact: AWS-only changes, applied operator-side; brief (single
  API call) window where operator CIDR isn't on the RDS SG during the
  one-time migration apply. No postgres-provider operations in the plan.
- Tests: N/A (no test suite in this repo).
- CI gates: `fmt -check -recursive`, `init`, `validate` — all pass-able
  locally without AWS creds.
