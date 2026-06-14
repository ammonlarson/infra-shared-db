# PR Reviewer Memory

## infra-shared-db (Terraform / shared RDS)

### CI architecture
- Two workflows. `terraform-lint.yml` = lint gate (`fmt -check` + `init` + `validate`),
  runs on every PR/push to main with NO path filter (intentional — see warning comment
  at top of the file). `terraform-apply.yml` = plan/apply via SSM bastion tunnel,
  path-filtered to Terraform-relevant files.
- `terraform-apply.yml` has a `wait-for-lint` gate that queries the Actions API for the
  lint run matching `head_sha` + `event`, releasing only on `conclusion == success`.
  Because of this, the lint workflow MUST keep firing on every PR/push (no path filter),
  or the apply gate waits until timeout.
- Lint gate needs no AWS: `terraform validate` does not read state, so
  `terraform init -backend=false` is sufficient and credential-free. This matches the
  repo's own `.githooks/pre-commit` (uses `init -backend=false -input=false`).
- `terraform-apply.yml`'s own `init` IS backend-enabled (needs state + RDS via tunnel)
  and keeps `id-token: write` + `AWS_REGION`. Don't flag those as leftovers.

### Adding a consumer (projects.tf + peering.tf + network.tf) — established pattern
- Per-project: add `<consumer>_staging`/`<consumer>_prod` to `local.projects` in projects.tf.
  `modules/project` already encodes the SECRET_SCHEMA.md payload (`database`/`host`/`password`/
  `port` int/`username`) — never edit the module per consumer.
- Peering accepter side mirrors greenspace/loppemarked exactly: a `local.<consumer>_peering` map
  (per-env `peering_tag_name`+`vpc_cidr`), `data aws_vpc_peering_connection` filtered by
  `tag:Name`+`status-code=active`+`accepter-vpc-info.vpc-id`, `aws_vpc_peering_connection_options`
  (accepter DNS), `aws_route`, and a dedicated `aws_security_group.rds` ingress block (5432,
  cidr_blocks from the map). Keep each consumer's SG ingress a SEPARATE block (independent revoke).
- CIDR collision rule: peered consumer VPCs route into the shared DEFAULT VPC's single main route
  table, so every consumer needs non-overlapping /16s. Allocation: greenspace 10.0/10.1,
  loppemarked 10.2/10.3, un17-resources 10.4/10.5. A ticket may specify colliding CIDRs (#66 said
  10.0/10.1) — flag and require non-overlapping reassignment.

### CI: the `Terraform plan` PR check (terraform-apply.yml) vs new-consumer peering
- This check DIALS RDS via the SSM tunnel (NOT the credential-free lint gate). It WILL fail on a
  new-consumer peering PR with `Error: no matching EC2 VPC Peering Connection found` because the
  consumer hasn't applied its requester side yet (tagged pcx doesn't exist). Documented operator-
  sequencing caveat, NOT a code defect — greenspace/loppemarked data sources resolve fine same run.
- Watch the plan summary line. `aws_instance.bastion` floats its AMI off the `al2023-ami-latest`
  SSM data source, so plans routinely show `aws_instance.bastion must be replaced` (ami forces
  replacement) as 1-change/1-destroy DRIFT unrelated to the PR. ADDING_A_PROJECT.md claims new-
  project plans are "additions only" — reconcile against this bastion noise; flag so an operator
  doesn't inadvertently replace the bastion (new instance id breaks the db_tunnel_command output).
  - RESOLVED by issue #68 / PR #69 (2026-06): `aws_instance.bastion` now has
    `lifecycle { ignore_changes = [ami] }`, so the AMI-drift replacement noise is GONE — plans
    no longer show the bastion replaced on unrelated applies. AMI refresh is now a deliberate
    `terraform apply -replace=aws_instance.bastion`. If a future PR's plan shows the bastion
    replaced, that's now a real signal (user_data change or explicit -replace), not drift.
    ADDING_A_PROJECT.md "additions only" gate is therefore once again literally true.

### Recurring pattern: config-sync commits ride along in PRs
- Branches are sometimes cut from the head of a prior bot config-sync PR (e.g. #62),
  so a feature PR's first commits are unrelated `agent: sync Claude Code configuration`
  commits touching CLAUDE.md / AGENTS.md / .mcp.json / .claude/. The PR body usually
  discloses this. Attribute findings per-commit (`git show --stat <sha>`); flag sync-commit
  defects as inherited/out-of-scope (belong in the sync PR), not against the feature commit.
- Those sync commits have shipped typos before (e.g. "Assigneed", "designed assignee",
  garbled "(s))"). Worth a quick scan when they appear.
