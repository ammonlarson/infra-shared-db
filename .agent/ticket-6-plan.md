# Ticket #6 — Plan

## Decision

**Option A: persist the operator IP in `terraform.tfvars` and re-apply on change.**

Operator IP for now: `90.184.18.6/32`.

## Analysis

### Current state

- `var.allowed_ingress_cidrs` defaults to `[]` (`variables.tf`).
- `aws_security_group.rds` ingress rule reads from that variable (`network.tf`).
- RDS is `publicly_accessible = true`, so the SG is the only firewall.
- `*.tfvars` is gitignored (`!*.tfvars.example` allowed), so the actual operator IP never lands in the repo.
- README mentions `terraform.tfvars` only in passing inside step 6 of the bootstrap; it's easy to miss.
- A routine `terraform apply` without `-var` will plan to drop the operator's CIDR back to `[]`.

### Target state

- Operator keeps a local, gitignored `terraform.tfvars` (not committed) containing their `/32`.
- Repo provides a committed `terraform.tfvars.example` template so the workflow is discoverable.
- README's Prerequisites + a dedicated "Operator IP / `terraform.tfvars`" section make the workflow hard to miss, and explicitly call out that running `apply` without it will silently propose removing ingress.
- `ADDING_A_PROJECT.md` is updated: because only the operator's IP is allowlisted (not GHA's egress range), GHA can do AWS-level applies but CANNOT do the Postgres-level provisioning for a new project. The operator must run `terraform apply` locally before (or after) merging the PR so the new database / role / secret get created.

### Approach

1. Add `terraform.tfvars.example` with the placeholder pattern (committed; it's whitelisted in `.gitignore`).
2. Create a local-only `terraform.tfvars` with `90.184.18.6/32` for the current operator (not committed).
3. Update `README.md`:
   - Promote the `terraform.tfvars` workflow into Prerequisites and a new "Operator IP / `terraform.tfvars`" section near the top of the operations content.
   - Note the silent-drop trap explicitly.
   - Note that GHA's apply will not be able to touch Postgres-level resources because only the operator's residential IP is allowlisted; AWS-level changes still go through CI as before.
4. Update `ADDING_A_PROJECT.md`:
   - Insert a "local apply" step before merge so the new DB/role/secret are provisioned from the operator's allowlisted IP.
   - Mirror the same caveat on the "Removing a project" section (the destroy of the Postgres-level resources also needs operator network reach).

## Task checklist

- [x] Read ticket #6
- [x] Add `agent active` + `claude` labels
- [x] Create plan doc
- [x] Confirm branch `claude/update-project-setup-Ysk1J` is checked out and clean
- [ ] Create `terraform.tfvars.example`
- [ ] Create local `terraform.tfvars` with `90.184.18.6/32` (uncommitted)
- [ ] Update `README.md`
- [ ] Update `ADDING_A_PROJECT.md`
- [ ] `terraform fmt -check -recursive`
- [ ] `terraform validate` (best effort — needs `init`; skip if state backend not reachable)
- [ ] Commit + push
- [ ] Open PR, run pr-reviewer, address feedback
- [ ] Add ammonl as reviewer
- [ ] Comment on issue, remove `agent active` label

## Files touched

| File | Change |
|---|---|
| `terraform.tfvars.example` | new — committed template |
| `terraform.tfvars` | new — local only (gitignored) |
| `README.md` | promote tfvars workflow, document silent-drop trap and CI-vs-local apply split |
| `ADDING_A_PROJECT.md` | add local-apply step, mirror on remove path |
| `.agent/ticket-6-plan.md` | this file |

No `.tf` source changes — this is a workflow + docs ticket only.

## Notes / risks

- Option A is explicitly the lower-effort, higher-toil choice. The trade-off is documented in the issue; revisit (B) or (C) next time the network layer is touched.
- We are NOT changing `var.allowed_ingress_cidrs` default away from `[]`. Defaulting to a residential IP in the tracked source would be worse than the current setup.
