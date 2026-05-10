# Ticket #7 — Plan

## Analysis

### Current state

- No committed Git hooks. `.git/hooks/` only contains the stock `*.sample` files.
- The only quality gate is the GitHub Actions workflow `.github/workflows/terraform.yml`, which runs:
  - `terraform fmt -check -recursive`
  - `terraform init`
  - `terraform validate`
  - `terraform plan`
- No standalone Terraform linter today.
- No commit-message convention is enforced locally; CI does not enforce one either.

### Target state

- Repo ships a `.githooks/` directory containing `pre-commit` and `commit-msg`, version-controlled.
- A small `scripts/install-hooks.sh` script sets `core.hooksPath = .githooks` for the clone (and warms up `tflint`).
- A real Terraform linter (tflint) is added with a minimal `.tflint.hcl` config so the pre-commit hook has a real lint step (not commit-msg validation as a stand-in).
- README documents the one-time setup and the Conventional Commits format.

### Approach

1. Add `.githooks/pre-commit` running, in order:
   - `terraform fmt -check -recursive` (formatter gate, same as CI)
   - `tflint --recursive` (lint gate; new — see below)
   - `terraform init -backend=false` + `terraform validate` (validation gate; backend skipped so the hook works without AWS creds)
   - `terraform plan` is intentionally **not** in the hook: it requires AWS creds, network reachability to RDS, and the operator IP in `allowed_ingress_cidrs`. CI is the canonical plan gate. Documented in the README.
2. Add `.githooks/commit-msg` with the EXACT script from the ticket.
3. Add `.tflint.hcl` enabling the bundled `terraform` plugin with the `recommended` preset (no remote-plugin download required, so first-time setup stays fast).
4. Add `scripts/install-hooks.sh` (one-line `git config core.hooksPath .githooks`, plus `tflint --init` if `tflint` is on PATH).
5. Update `README.md` with a "Contribution Guidelines" section: hook setup, prerequisites (`terraform`, `tflint`), and the Conventional Commits format with allowed types and the 72-char limit.

## Task checklist

- [x] Read ticket #7
- [x] Add `agent active` + `claude` labels
- [x] Create plan doc
- [x] Branch already on `claude/complete-ticket-7-moeFy`
- [ ] Add `.githooks/pre-commit`
- [ ] Add `.githooks/commit-msg` (verbatim from ticket)
- [ ] Add `.tflint.hcl`
- [ ] Add `scripts/install-hooks.sh`
- [ ] Update `README.md` (Contribution Guidelines + prerequisites)
- [ ] `terraform fmt -check -recursive`
- [ ] `terraform validate` (best effort — backend not reachable in this sandbox; document if skipped)
- [ ] Smoke-test the hooks locally (run them by hand against a sample message)
- [ ] Commit + push
- [ ] Open PR, run pr-reviewer, address feedback
- [ ] Add ammonl as reviewer
- [ ] Comment on issue, remove `agent active` label

## Files touched

| File | Change |
|---|---|
| `.githooks/pre-commit` | new — fmt / tflint / validate gate |
| `.githooks/commit-msg` | new — verbatim Conventional Commits enforcement |
| `.tflint.hcl` | new — minimal tflint config |
| `scripts/install-hooks.sh` | new — opt-in hook activation |
| `README.md` | new "Contribution Guidelines" section + tflint prerequisite |
| `.agent/ticket-7-plan.md` | this file |
| `.vscode/launch.json` | new — VS Code launch config to run `.githooks/pre-commit` from the Run/Debug panel |

No `.tf` source changes — this ticket is workflow / docs only.

## Notes / risks

- `core.hooksPath` is the supported, version-controlled mechanism (no extra dependency like Husky / pre-commit.com). It's a single `git config` away.
- `terraform plan` is intentionally not in the pre-commit hook; documented in README. CI runs it on every PR.
- tflint's `terraform` plugin is bundled with the binary, so `.tflint.hcl` works without `tflint --init`. If the AWS plugin is ever wanted, `install-hooks.sh` already runs `tflint --init` when tflint is present.
