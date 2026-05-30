# Ticket 36 — Bastion-style DB access path for operators and CI

## Decision (from operator)

- **Access pattern:** SSM port-forwarding to a **private** RDS. Flip
  `publicly_accessible = false`, drop `allowed_ingress_cidrs`, reach Postgres
  through an SSM-managed bastion (no inbound SG, no public DB endpoint).
- **Lifecycle:** **always-on** `t4g.nano` (~$7-8/mo). No NAT, no SSM VPC
  endpoints — the agent reaches SSM outbound via the default VPC's IGW using an
  auto-assigned public IPv4. The public IP does not expose RDS (RDS is private,
  SSM needs no inbound).

This closes #6 (residential-IP dependency) instead of leaving two competing
workflows documented.

## Current state

- `rds.tf`: `publicly_accessible = true`; SG is the only firewall.
- `network.tf`: RDS SG ingress = `var.allowed_ingress_cidrs` + Greenspace peering CIDRs.
- `providers.tf`: postgresql provider dials `aws_db_instance.shared.address` directly.
- `variables.tf`: `allowed_ingress_cidrs` (operator `/32`).
- CI: lint-only; `plan`/`apply` operator-side because the GHA runner IP isn't allowlisted.

## Target state

- RDS private; SG ingress = bastion SG + Greenspace peering CIDRs only.
- New `bastion.tf`: `t4g.nano` AL2023 arm64, SSM instance profile, egress-only SG,
  public IP for SSM egress, IMDSv2, encrypted root.
- postgresql provider points at `var.postgres_host`/`var.postgres_port`
  (default `127.0.0.1:5432`) — i.e. through the SSM tunnel. Tunnel becomes
  mandatory for any Postgres-level plan/apply.
- `scripts/db-tunnel.sh`: operator helper to open the SSM port-forward.
- `.github/workflows/terraform-apply.yml`: `workflow_dispatch` plan/apply that
  opens the SSM tunnel on the runner, so CI can refresh `postgresql_role` /
  `postgresql_database` when needed.
- IAM policy (`policies/gha-terraform-shared-db.json`): add bastion lifecycle +
  `ssm:StartSession` on the bastion + port-forward document + AMI param read.
- Remove `allowed_ingress_cidrs` and repurpose `terraform.tfvars.example`.
- Docs: rewrite the network / operator / CI sections in README.md and the
  heads-up in ADDING_A_PROJECT.md.

## Task checklist

- [ ] `rds.tf`: `publicly_accessible = false`
- [ ] `network.tf`: RDS SG ingress from bastion SG (+ peering CIDRs)
- [ ] `bastion.tf`: instance, SG, IAM role + instance profile, AMI data source
- [ ] `providers.tf` + `variables.tf`: tunnel-based postgres host/port
- [ ] `outputs.tf`: bastion id, RDS endpoint, copy-paste tunnel command
- [ ] `scripts/db-tunnel.sh`: operator tunnel helper
- [ ] `.github/workflows/terraform-apply.yml`: CI plan/apply through the tunnel
- [ ] `policies/gha-terraform-shared-db.json`: new permissions
- [ ] Remove `allowed_ingress_cidrs`; repurpose `terraform.tfvars.example`
- [ ] README.md + ADDING_A_PROJECT.md docs
- [ ] `terraform fmt -check -recursive`

## Validation note

The acceptance criteria that require *exercising* the path (a real operator run
and a real CI run against live AWS) can't be executed from this sandbox — no AWS
creds / RDS reachability here. Those must be run operator-side after merge; the
PR will call this out explicitly along with the documented migration sequence.

## Migration (chicken-and-egg)

First apply that flips RDS private also creates the bastion, but the postgres
provider would try to refresh existing roles through a tunnel that doesn't exist
yet. Documented two-phase apply:
1. `terraform apply -target=aws_instance.bastion` (+ its SG/IAM) while RDS is
   still public — provider not invoked since no postgres resource is targeted.
2. Open the tunnel through the new bastion, then full `terraform apply` (RDS
   flips private, SG changes, postgres resources refresh through the tunnel).
