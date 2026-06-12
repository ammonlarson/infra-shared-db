## Project Settings

- **Ticket Provider**: GitHub Issues
- **Branch Format**: `<type>/<ticket-number>` (e.g., `feature/123`)
- **Main Branch**: `main`
- **Designated Assignee(s)**: @ammonl

## What this repo is

A single Terraform root module that provisions one shared Postgres RDS instance and carves out an isolated database + login role + Secrets Manager secret per project. There is no application code — only `.tf` files and the GitHub Actions workflow that applies them.

The unit of change is almost always a one-line edit to `local.projects` in `projects.tf`. Anything bigger usually means rethinking the architecture, not adding code.

## Common commands

```bash
terraform fmt -check -recursive   # CI runs this; matches the lint gate
terraform init                    # required after backend or provider changes
terraform validate
scripts/db-tunnel.sh              # open the SSM tunnel (separate terminal) before plan/apply
terraform plan
terraform apply
```

RDS is private (`publicly_accessible = false`). Any plan/apply that touches Postgres-level resources needs an open SSM tunnel to the bastion — the `postgresql` provider connects to `var.postgres_host`/`var.postgres_port` (default `127.0.0.1:15432`, where 15432 avoids colliding with a local Postgres), which is what `scripts/db-tunnel.sh` maps. There is no `allowed_ingress_cidrs` and no operator-IP `terraform.tfvars`.

There are no tests, no build step, and no `npm` / language tooling in this repo. CI has two workflows: `terraform-lint.yml` is the lint gate (`fmt -check` + `init -backend=false` + `validate`) on every PR/push and never dials RDS or AWS; `terraform-apply.yml` opens the same tunnel on the runner and runs `terraform plan` on PRs to `main`, `terraform apply` on pushes to `main` (both path-filtered to Terraform-relevant files), plus a manual `workflow_dispatch` plan/apply, and is gated on a successful `terraform-lint.yml` run for the same change. See the README's "Operator DB/Terraform access (SSM tunnel)" section.

## Architecture — what requires reading multiple files

### Two providers, one apply

`providers.tf` configures both the `aws` provider and `cyrilgdn/postgresql`. The Postgres provider's connection string is derived from the RDS instance attributes that don't exist until AWS-level resources are applied. Terraform handles this implicitly via the dependency graph, but it has two consequences:

1. **First apply is fragile.** The provider tries to dial RDS during plan. On a brand-new state, `terraform plan` may fail until the RDS instance exists. The README's troubleshooting section documents the `role already exists` race; re-running apply is the standard fix. Migrating an existing public-RDS state to the private + bastion model needs the targeted bootstrap apply documented in README's "First Terraform apply".
2. **The SSM tunnel must be open wherever you run `terraform plan/apply`.** RDS is private; the provider reaches it through `scripts/db-tunnel.sh` (operator laptop) or the tunnel the `terraform-apply.yml` job opens on the runner. The bastion (`bastion.tf`, a `t4g.nano`) is the only inbound path and carries no inbound SG rules — Session Manager is outbound-only. See "Network access caveats" in README.md.

### The per-project module is the only place projects exist

`modules/project/main.tf` defines what "a project" means: one `random_password`, one `postgresql_role`, one `postgresql_database`, and one `aws_secretsmanager_secret` + version. `projects.tf` instantiates this module via `for_each` over `local.projects`. To add or remove a project you edit only the list in `projects.tf` — never the module.

A project's identity is its name string. Renaming is a destroy-and-recreate (see ADDING_A_PROJECT.md FAQ). Project names are lowercase `snake_case`, no leading digits, and become the database name, the role `<name>_app`, and the secret `rds/shared/<name>`.

### State backend is bootstrapped out-of-band

`backend.tf` references an S3 bucket (`ammonl-db-tf-state`) and DynamoDB lock table (`ammonl-db-tf-locks`) in `eu-north-1`. These exist outside of Terraform's control because of the chicken-and-egg with the state backend — see README.md "One-time bootstrap" for how they were created. Don't try to manage them via this repo.

### CI/CD: lint gate plus bastion plan/apply

`.github/workflows/terraform-lint.yml` runs `fmt -check`, `init -backend=false`, and `validate` on every PR and push to `main` — the lint gate never dials RDS or AWS and needs no credentials. `.github/workflows/terraform-apply.yml` opens the SSM tunnel on the runner so CI can refresh Postgres-level resources: it runs `terraform plan` on PRs to `main` (the authoritative diff, plan only — it never applies on a PR), `terraform apply` automatically on push to `main`, and a manual `workflow_dispatch` plan/apply, all path-filtered to Terraform-relevant files. The apply workflow is gated on the lint gate: a `wait-for-lint` job blocks the plan/apply job until the `terraform-lint.yml` run for the same change (head SHA + event) concludes successfully — a failed lint skips the plan/apply, an in-progress lint makes it wait, and `workflow_dispatch` skips the gate. AWS auth (apply workflow only) is GitHub OIDC against the IAM role `gha-terraform-shared-db`; the role exists so the apply workflow's `init` can read the S3 backend, manage the bastion, and open the port-forward. The PR plan posts the authoritative diff in CI — verify it matches what ADDING_A_PROJECT.md describes (only additions for new projects, only destroys for removals); you can still reproduce it locally with the tunnel open.

## Conventions

- AWS region is `eu-north-1` everywhere (variable default + GHA env). Don't hardcode it elsewhere.
- The master credential lives at `rds/shared/master`; per-project secrets at `rds/shared/<name>`. Project apps must only have IAM access to their own secret ARN, never the master.
- Pre-existing resources (`deletion_protection = true`, `skip_final_snapshot = false`, `final_snapshot_identifier`) on `aws_db_instance.shared` are intentional safety guards. Don't remove them when refactoring.
- RDS is `publicly_accessible = false`; the bastion SG is its only IP-less ingress (plus peered Greenspace CIDRs). Don't reintroduce a public endpoint or an operator-IP allowlist.
- `*.tfvars` is gitignored; `terraform.tfvars.example` (whitelisted) is now only an optional template for the `postgres_port` tunnel override. Don't commit a `terraform.tfvars`.
