# Shared-DB secret payload schema

This document describes the JSON payload stored in every Secrets Manager
secret managed by this repo. It is the **canonical, version-controlled
contract** for consumers reading from `rds/shared/<project>` (and, where
applicable, `rds/shared/master`).

> Source of truth: `modules/project/main.tf`
> ([`aws_secretsmanager_secret_version.app`](./modules/project/main.tf)).
> The master secret in [`rds.tf`](./rds.tf) uses the same field names.
>
> Machine-readable contract: [`schemas/secret.schema.json`](./schemas/secret.schema.json)
> (JSON Schema). Enforce it with [`scripts/verify-secret-shape.sh`](./scripts/verify-secret-shape.sh) —
> see [Verifying a live secret](#verifying-a-live-secret).

## Why this doc exists

The shared-db Secrets Manager secret keys do **not** match the AWS-managed
RDS rotation-Lambda format. In particular, the database name is keyed
`database` here — not `dbname` as the AWS rotation Lambda would write. A
consumer written against the wrong shape will deserialize successfully and
then fail at connection time because the field it reads is missing.
That trap caused a production incident in the `greenspace` consumer
(`ammonlarson/greenspace` PRs #346 and #348). Before merging any consumer
PR that reads one of these secrets, run the [verification step](#verifying-a-live-secret)
below.

## Payload shape

The `SecretString` is a JSON object with exactly the following keys:

| Field      | Type     | Stability        | Required | Meaning                                                       |
| ---------- | -------- | ---------------- | -------- | ------------------------------------------------------------- |
| `database` | `string` | Stable contract  | Yes      | Postgres database name (matches the project name).            |
| `host`     | `string` | Stable contract  | Yes      | RDS endpoint hostname (e.g. `shared-postgres.<id>.<region>.rds.amazonaws.com`). |
| `password` | `string` | Stable contract  | Yes      | Password for `username`. Rotates when the operator runs `terraform taint` on the project's `random_password.app`. |
| `port`     | `number` | Stable contract  | Yes      | TCP port (currently `5432`). JSON `number`, not a string.     |
| `username` | `string` | Stable contract  | Yes      | Login role name. Always `<project>_app` for per-project secrets; `tfadmin` for the master secret. |

All five fields above are part of the **stable consumer contract**: a
consumer building a Postgres connection string must read every one. The
contract is owned by this repo and changes here will require coordinated
updates in every consumer.

### Example payload

```json
{
  "host": "shared-postgres.cabcd1234.eu-north-1.rds.amazonaws.com",
  "port": 5432,
  "database": "greenspace_staging",
  "username": "greenspace_staging_app",
  "password": "<32-char random>"
}
```

### What is not in the payload

The following fields are **not** present today and **must not** be relied
on by consumers:

- `dbname` — the AWS RDS rotation-Lambda key for the database name. This
  repo uses `database` instead. If your consumer reads `dbname`, it is
  reading the wrong key.
- `engine`, `dbInstanceIdentifier`, `dbClusterIdentifier`,
  `masterarn` — fields the AWS-managed RDS rotation Lambda would add. AWS
  rotation is not configured on these secrets, so none of these keys exist.
- `host` aliases such as `endpoint` or `proxy_host`. There is one host
  field, named `host`.

If any of these are added in the future, they will be **optional /
implementation-detail** fields unless explicitly promoted to the stable
contract table above. New optional fields may appear without a major
contract bump; consumers should only read them with explicit fallbacks.

## Verifying a live secret

Before merging a consumer PR that reads a shared-db secret, verify the live
payload against the contract for **every** environment the consumer targets.

### Automated check (preferred)

Use [`scripts/verify-secret-shape.sh`](./scripts/verify-secret-shape.sh). It
fetches the secret and validates it against
[`schemas/secret.schema.json`](./schemas/secret.schema.json) — every required
field must be present with the correct JSON type — and exits non-zero on
mismatch. Because it returns a non-zero exit code, it drops straight into a
consumer's CI or deploy pipeline; no operator has to read `jq` output by eye.

```bash
scripts/verify-secret-shape.sh rds/shared/<project> <aws-region>
```

Region resolution: the second argument, else `$AWS_REGION`, else `eu-north-1`.
Run it once per environment (e.g. `rds/shared/greenspace_staging` **and**
`rds/shared/greenspace_prod`); staging and prod can diverge in principle, so a
single check is not sufficient.

To validate a payload you already have (e.g. from another tool) without an AWS
call, pipe it in:

```bash
echo "$secret_json" | scripts/verify-secret-shape.sh --stdin
```

Only the stable contract fields are required, so optional/implementation-detail
fields (see [What is not in the payload](#what-is-not-in-the-payload)) can be
added later without making this check fail.

### Manual fallback (one-liner)

If you can't run the script, fetch the keys directly and cross-check them
against the field names referenced in the consuming code:

```bash
aws secretsmanager get-secret-value \
  --secret-id rds/shared/<project> \
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

If the live payload does not match the consuming code, **do not merge** —
update the consumer to read the names listed in the [Payload shape](#payload-shape)
table.

## Where the schema is set

Per-project secrets are written by
[`modules/project/main.tf`](./modules/project/main.tf):

```hcl
resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    host     = var.db_host
    port     = var.db_port
    database = postgresql_database.app.name
    username = postgresql_role.app.name
    password = random_password.app.result
  })
}
```

The master secret in [`rds.tf`](./rds.tf) uses the same five keys. Any
change to the field set must be made in both places, in this doc, and
coordinated with every consumer.

## Related

- [`ADDING_A_PROJECT.md`](./ADDING_A_PROJECT.md) — wiring a project's
  runtime to its secret, including the pre-merge verification step.
- [`README.md`](./README.md#connecting-from-a-project-repo) — example
  Python that reads the secret and builds a `DATABASE_URL`.
- [`schemas/secret.schema.json`](./schemas/secret.schema.json) — the
  machine-readable contract. Consumers can pin its `$id` as a `$schema` ref
  and validate at runtime or in CI.
- [`scripts/verify-secret-shape.sh`](./scripts/verify-secret-shape.sh) — fetches
  a secret and validates it against the schema, exiting non-zero on mismatch.
