# Adding a project

When a new project needs a database, do this.

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

GitHub Actions runs `terraform plan` and posts the diff as a comment. Verify the plan shows only **additions** for the new project:

- `random_password` (the app role's password)
- `postgresql_role`
- `postgresql_database`
- `aws_secretsmanager_secret`
- `aws_secretsmanager_secret_version`

If anything is being **destroyed**, stop and investigate before merging.

## 4. Merge

Apply runs after manual approval in the `production` environment. The new secret appears at:

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

## 6. Run migrations

Use the project's existing migration tooling (Alembic, Prisma, etc.) against `DATABASE_URL`. Nothing about migrations changes — the project owns its database and can do whatever it wants inside it.

## Removing a project

1. Take a `pg_dump` if you might want the data later (see the operations section in the main README).
2. Remove the entry from `projects.tf`.
3. Open a PR.
4. The plan will show **destroys** for that project's database, role, password, and secret. Confirm only that project's resources are affected.
5. Merge. The database and its data are gone after apply. The Secrets Manager secret is scheduled for deletion (default 30-day recovery window).

## FAQ

**Can I change a project's name?**
No clean rename — Terraform will plan to destroy and recreate. Add the new name, migrate data with `pg_dump | psql`, then remove the old entry.

**Can two projects share a database?**
They shouldn't. The whole point of this repo is isolation. If two services genuinely share data, they belong in one project.

**Can I run migrations from a separate "migrations" workflow?**
Yes — the project repo's CI reads its secret and runs migrations exactly as it would against any other Postgres host. This repo doesn't care.
