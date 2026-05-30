# Adding a project

When a new project needs a database, do this.

> **Migrating an existing repo off its own dedicated DB?** This page is the
> greenfield happy path. If the consumer already runs on a dedicated database
> and you're moving it onto shared-db (provision, peer, cut over, retire the old
> DB), follow [`MIGRATING_AN_EXISTING_PROJECT.md`](./MIGRATING_AN_EXISTING_PROJECT.md)
> instead — it wraps these mechanics in the full two-repo migration sequence.

> **Heads-up:** RDS is private. Any `terraform plan`/`apply` that touches Postgres-level resources needs an open SSM tunnel to the bastion — start `scripts/db-tunnel.sh` first. You can run plan/apply from your laptop (through the tunnel) or via the manual `Terraform apply (via SSM bastion)` CI workflow, which opens the tunnel on the runner. The PR lint gate (`fmt`/`init`/`validate`) never deploys. See [Operator DB/Terraform access](./README.md#operator-dbterraform-access-ssm-tunnel) in `README.md`.

## 1. Pick a name

Use lowercase `snake_case`, no leading digits. The name becomes:

- The Postgres database name
- The login role: `<name>_app`
- The Secrets Manager secret: `rds/shared/<name>`
- The entry in `projects.tf`

Examples: `curtain_call`, `loppemarked_2026`, `interhuman_blog`.

If your project has multiple deployment environments (staging, production), use one entry per environment with a `<project>_<env>` suffix — see [Per-environment projects](./README.md#per-environment-projects) in `README.md`.

## 2. Add it to `projects.tf`

```hcl
locals {
  projects = [
    "proj_a",
    "proj_b",
    "proj_c",   # new
  ]
}
```

## 3. Plan locally and open a PR

CI will run `fmt`/`init`/`validate` on the PR but won't produce a diff. Run `terraform plan` from your laptop to get the authoritative plan:

```bash
git checkout <your-branch>
terraform plan
```

Verify the plan shows only **additions** for the new project:

- `random_password` (the app role's password)
- `postgresql_role`
- `postgresql_database`
- `aws_secretsmanager_secret`
- `aws_secretsmanager_secret_version`

If anything is being **destroyed**, stop and investigate before merging.

## 4. Apply locally, then merge

Apply from your laptop while you're still on the branch:

```bash
terraform apply
```

Then merge the PR. CI's lint job runs against `main` but does no further work. The new secret appears at:

```
arn:aws:secretsmanager:<region>:<account>:secret:rds/shared/<name>
```

## 5. Wire the secret into the project

In the project's deployment, give its runtime IAM role permission to read just that one secret:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "secretsmanager:GetSecretValue",
    "Resource": "arn:aws:secretsmanager:<region>:<account>:secret:rds/shared/<name>-*"
  }]
}
```

Set `DB_SECRET_ID=rds/shared/<name>` as a runtime env var. Read it at startup:

```python
import boto3, json, os

raw = boto3.client("secretsmanager").get_secret_value(
    SecretId=os.environ["DB_SECRET_ID"]
)
c = json.loads(raw["SecretString"])
DATABASE_URL = f"postgresql://{c['username']}:{c['password']}@{c['host']}:{c['port']}/{c['database']}"
```

The exact JSON field names (`database`, `host`, `password`, `port`, `username`) are documented in [`SECRET_SCHEMA.md`](./SECRET_SCHEMA.md). Note that the database name is keyed `database` — **not** `dbname`, as the AWS-managed RDS rotation Lambda would write. A consumer that reads `dbname` will get a missing/null value (depending on the language) and fail at connection time.

## 6. Verify the live secret payload before merging

Before merging the consumer PR, check the live payload against the contract for **every** environment the consumer targets. Run [`scripts/verify-secret-shape.sh`](./scripts/verify-secret-shape.sh) — it fetches the secret and checks that every required field in [`schemas/secret.schema.json`](./schemas/secret.schema.json) is present with the correct JSON type, exiting non-zero on mismatch, so it can run in the consumer's CI/deploy pipeline instead of being eyeballed:

```bash
scripts/verify-secret-shape.sh rds/shared/<name> <aws-region>
```

Region resolution: the second argument, else `$AWS_REGION`, else `eu-north-1`.

Run it separately for **every** environment the consumer targets. For per-environment projects (see [Per-environment projects](./README.md#per-environment-projects) in `README.md`) the environment suffix is part of the project name itself, so the secret IDs are e.g. `rds/shared/greenspace_staging` and `rds/shared/greenspace_prod` — there is no separate "base" project. Check each one. Staging and prod can diverge in principle, so checking one is not sufficient.

If verification fails, do **not** merge — fix the consumer to use the names in [`SECRET_SCHEMA.md`](./SECRET_SCHEMA.md) first. This step exists because skipping it caused a production incident in the `greenspace` consumer (`ammonlarson/greenspace` #346 / #348).

### Manual fallback (one-liner)

If you can't run the script, fetch the keys directly and cross-check them against the field names referenced in the consuming code:

```bash
aws secretsmanager get-secret-value \
  --secret-id rds/shared/<name> \
  --region <aws-region> \
  --query SecretString --output text | jq 'keys'
```

Expected output:

```json
[
  "database",
  "host",
  "password",
  "port",
  "username"
]
```

## 7. Run migrations

Use the project's existing migration tooling (Alembic, Prisma, etc.) against `DATABASE_URL`. Nothing about migrations changes — the project owns its database and can do whatever it wants inside it.

## Removing a project

1. Take a `pg_dump` if you might want the data later (see the operations section in the main README).
2. Remove the entry from `projects.tf`.
3. Run `terraform plan` locally and open a PR.
4. The plan will show **destroys** for that project's database, role, password, and secret. Confirm only that project's resources are affected.
5. Run `terraform apply` from your laptop, then merge. The database and its data are gone after the local apply. The Secrets Manager secret is scheduled for deletion (default 30-day recovery window).

## FAQ

**Can I change a project's name?**
No clean rename — Terraform will plan to destroy and recreate. Add the new name, migrate data with `pg_dump | psql`, then remove the old entry.

**Can two projects share a database?**
They shouldn't. The whole point of this repo is isolation. If two services genuinely share data, they belong in one project.

**Can I run migrations from a separate "migrations" workflow?**
Yes — the project repo's CI reads its secret and runs migrations exactly as it would against any other Postgres host. This repo doesn't care.
