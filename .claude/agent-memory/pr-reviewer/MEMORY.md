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

### Recurring pattern: config-sync commits ride along in PRs
- Branches are sometimes cut from the head of a prior bot config-sync PR (e.g. #62),
  so a feature PR's first commits are unrelated `agent: sync Claude Code configuration`
  commits touching CLAUDE.md / AGENTS.md / .mcp.json / .claude/. The PR body usually
  discloses this. Attribute findings per-commit (`git show --stat <sha>`); flag sync-commit
  defects as inherited/out-of-scope (belong in the sync PR), not against the feature commit.
- Those sync commits have shipped typos before (e.g. "Assigneed", "designed assignee",
  garbled "(s))"). Worth a quick scan when they appear.
