# Adding a project

When a new project needs a database, do this.

> **Heads-up:** project provisioning uses the `postgresql` provider, which has to reach RDS over the network. Only the operator's IP is in `allowed_ingress_cidrs`, not the GHA runner's, so the CI `apply` will fail on the Postgres-level resources. **You run `terraform apply` from your laptop** for project changes. Make sure your `terraform.tfvars` is up to date before you start — see the [Operator IP](./README.md#operator-ip-and-terraformtfvars) section in `README.md`.

## 1. Pick a name

Use lowercase `snake_case`, no leading digits. The name becomes:

- The Postgres database name
- The login role: `<name>_app`
- The Secrets Manager secret: `rds/shared/<name>`
- The entry in `projects.tf`

Examples: `curtain_call`, `loppemarked_2026`, `interhuman_blog`.

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

## 3. Open a PR

GitHub Actions runs `terraform plan`. The PR plan will fail on the Postgres-level resources because the GHA runner can't reach RDS — that's expected. Run `terraform plan` locally too, where the `postgresql` provider can connect:

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

Because CI can't apply the Postgres-level resources, **apply from your laptop first** while you're still on the branch:

```bash
terraform apply
```

Then merge the PR. The CI `apply` job runs against `main` and will be a no-op for the Postgres-level resources (state already matches). The new secret appears at:

```
arn:aws:secretsmanager:<region>:<account>:secret:rds/shared/<name>
```

If you'd rather merge first and apply after, that works too — but the `production` environment will sit waiting and the apply job will fail on the Postgres-level resources. Apply locally to clear it.

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

## 6. Run migrations

Use the project's existing migration tooling (Alembic, Prisma, etc.) against `DATABASE_URL`. Nothing about migrations changes — the project owns its database and can do whatever it wants inside it.

## Removing a project

1. Take a `pg_dump` if you might want the data later (see the operations section in the main README).
2. Remove the entry from `projects.tf`.
3. Open a PR. CI `plan` will fail on the Postgres-level destroys for the same reason adds do — run `terraform plan` locally to verify.
4. The plan will show **destroys** for that project's database, role, password, and secret. Confirm only that project's resources are affected.
5. Run `terraform apply` from your laptop to drop the Postgres-level resources, then merge. The database and its data are gone after the local apply. The Secrets Manager secret is scheduled for deletion (default 30-day recovery window).

## FAQ

**Can I change a project's name?**
No clean rename — Terraform will plan to destroy and recreate. Add the new name, migrate data with `pg_dump | psql`, then remove the old entry.

**Can two projects share a database?**
They shouldn't. The whole point of this repo is isolation. If two services genuinely share data, they belong in one project.

**Can I run migrations from a separate "migrations" workflow?**
Yes — the project repo's CI reads its secret and runs migrations exactly as it would against any other Postgres host. This repo doesn't care.
