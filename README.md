# infra-shared-db

Shared Postgres infrastructure for low-volume projects. One RDS instance hosts multiple isolated databases — one per project — with per-project credentials managed in AWS Secrets Manager.

## Architecture

- One `db.t4g.micro` RDS Postgres instance, managed entirely by Terraform.
- Each project gets its own logical database, login role, and randomly generated password.
- Each project's connection string lives in its own Secrets Manager secret at `rds/shared/<project>`.
- Project repos read their secret at runtime. They never see the master credentials or any other project's secret.
- Adding a project = appending a name to a list and merging a PR.

```
                         ┌──────────────────────────┐
                         │   shared-postgres (RDS)  │
                         │                          │
   project A app ──▶ ─── │ ▶ database: proj_a       │
                         │   role: proj_a_app       │
                         │                          │
   project B app ──▶ ─── │ ▶ database: proj_b       │
                         │   role: proj_b_app       │
                         └──────────────────────────┘
                                     ▲
                                     │ master creds
                         ┌──────────────────────────┐
                         │      Secrets Manager     │
                         │  rds/shared/master       │
                         │  rds/shared/proj_a       │
                         │  rds/shared/proj_b       │
                         └──────────────────────────┘
```

## Repo layout

```
.
├── .github/workflows/terraform.yml
├── modules/project/
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── backend.tf
├── versions.tf
├── providers.tf
├── network.tf
├── peering.tf
├── rds.tf
├── projects.tf
├── outputs.tf
├── variables.tf
├── README.md
└── ADDING_A_PROJECT.md
```

## Prerequisites

- AWS account with admin access (for one-time bootstrap only)
- `aws` CLI configured locally
- The [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) for the `aws` CLI. RDS is private; every `terraform plan`/`apply` that touches Postgres-level resources, and every `psql` session, goes through an SSM tunnel — see [Operator DB/Terraform access (SSM tunnel)](#operator-dbterraform-access-ssm-tunnel).
- `terraform` >= 1.6
- [`tflint`](https://github.com/terraform-linters/tflint) (used by the local pre-commit hook)
- `gh` CLI (optional, for repo creation)

## Contribution guidelines

### Enable the local Git hooks

This repo ships its hooks in `.githooks/` so every contributor runs the same
local quality gates. Activate them once per clone:

```bash
./scripts/install-hooks.sh
```

That sets `core.hooksPath = .githooks` for this clone and (if `tflint` is on
your PATH) initializes its plugins. No global tooling, no `npm`, no Husky.

The hooks installed:

- **`pre-commit`** — mirrors the CI quality gates that don't need AWS creds:
  - `terraform fmt -check -recursive`
  - `tflint --recursive` (config: [`.tflint.hcl`](./.tflint.hcl))
  - `terraform init -backend=false` + `terraform validate`

  `terraform plan` is intentionally not in the hook: it requires AWS
  credentials and an open SSM tunnel to the private RDS instance (see
  [Operator DB/Terraform access](#operator-dbterraform-access-ssm-tunnel)).
  The PR lint job never dials RDS.

  > The first commit after `install-hooks.sh` runs `terraform init -backend=false`,
  > which downloads the `aws` and `cyrilgdn/postgresql` providers (~30s, cached
  > under `.terraform/`). Subsequent commits use the cache and are fast.

- **`commit-msg`** — enforces [Conventional Commits](https://www.conventionalcommits.org/)
  with a 72-character summary limit. See the next section.

To bypass the hooks for a single commit (e.g. a work-in-progress save), use
`git commit --no-verify`. Don't make a habit of it.

### Commit message format

Commits must match:

```
<type>[(<scope>)]: <summary>
```

- **Allowed types:** `feat`, `fix`, `docs`, `refactor`, `perf`, `test`,
  `build`, `ci`, `chore`, `revert`, `i18n`, `ui`, `agent`, `infra`, `ux`.
- **Scope** (optional) is lowercase, alphanumeric, with `-` or `_`.
- **Summary** is the first line; total length (type + scope + summary) must
  be 72 characters or fewer.
- Merge commits (`Merge ...`) are passed through.

Examples:

```
feat(projects): add greenspace project
fix(rds): tighten ingress to operator /32
docs: clarify local apply for Postgres-level changes
```

The hook prints a targeted diagnostic on rejection (missing type, unclosed
scope, missing colon, missing space, message too long, etc.).

## Operator DB/Terraform access (SSM tunnel)

> **Read this before your first `terraform plan` or `apply`.** RDS is private — without an open tunnel, any plan that touches Postgres-level resources will hang or fail to connect.

The RDS instance is `publicly_accessible = false`. There is no public endpoint and no IP allowlist to maintain; the only inbound path to Postgres is an always-on SSM **bastion** (`aws_instance.bastion`, a `t4g.nano` defined in `bastion.tf`). The bastion carries **no inbound security-group rules** — Session Manager works entirely over the agent's outbound connection — so nothing is exposed to the internet. This replaces the old residential-IP allowlist that issue #6 tracked; `var.allowed_ingress_cidrs` is gone.

Because the `cyrilgdn/postgresql` provider has to reach Postgres to manage `postgresql_role` / `postgresql_database`, every `terraform plan`/`apply` once a project exists in state — and any manual `psql` — goes through a port-forward to the bastion. The provider defaults to `127.0.0.1:5432` (`var.postgres_host` / `var.postgres_port`), which is exactly what the tunnel maps.

**Open the tunnel** (leave it running in its own terminal):

```bash
scripts/db-tunnel.sh           # maps localhost:5432 -> private RDS via the bastion
```

The script finds the bastion (by its `Name=shared-db-bastion` tag) and the RDS endpoint for you, then runs `aws ssm start-session ... AWS-StartPortForwardingSessionToRemoteHost`. Terraform also emits a ready-to-paste equivalent as the `db_tunnel_command` output.

**Run Terraform / psql** against localhost in another terminal:

```bash
terraform plan
terraform apply

# or connect directly:
psql "host=127.0.0.1 port=5432 user=tfadmin dbname=postgres sslmode=require"
```

**Close it** when done: `Ctrl-C` in the tunnel terminal ends the session.

If port 5432 is already taken locally, forward to another port and tell Terraform:

```bash
scripts/db-tunnel.sh 15432
terraform plan -var='postgres_port=15432'
```

You no longer need a `terraform.tfvars` for routine work — the defaults match the tunnel. `terraform.tfvars.example` remains as an optional template for the port override (it's whitelisted by `.gitignore`'s `!*.tfvars.example`).

### What runs where

| Task | Where it runs | Needs the tunnel? |
| --- | --- | --- |
| `fmt -check`, `init`, `validate` (lint gate) | CI on every PR/push (`terraform.yml`) | No — never dials RDS |
| `terraform plan` / `apply` (laptop) | Operator laptop | Yes — open `scripts/db-tunnel.sh` first |
| `terraform plan` / `apply` (CI) | `workflow_dispatch` job (`terraform-apply.yml`) | Yes — the job opens the tunnel on the runner |
| `psql`, `pg_dump`, password rotation | Operator laptop | Yes |

### Running plan/apply from CI

Unlike before, CI **can** now refresh Postgres-level resources. The `Terraform apply (via SSM bastion)` workflow (`.github/workflows/terraform-apply.yml`) is a manual `workflow_dispatch` with a `plan`/`apply` choice. It authenticates via the existing GitHub OIDC role, installs the Session Manager plugin, opens the same SSM port-forward on the runner (so the provider reaches RDS at `127.0.0.1:5432`), then runs the chosen Terraform action.

It is intentionally **not** wired to push/PR: applies stay a deliberate act. The bastion must already exist — it is bootstrapped operator-side (see [First Terraform apply](#6-first-terraform-apply)). Use this workflow for routine project-change applies; use a laptop tunnel for the initial bootstrap and anything interactive.

If you want CI to deploy end-to-end, see option (B) or (C) in issue #6 — both lift this constraint, at the cost of more infra.

## One-time bootstrap

A few resources can't be managed by Terraform itself (chicken-and-egg with the state backend, plus the OIDC trust). Create them once by hand.

### 1. Set environment variables

Pick names and a region. These are referenced throughout this section.

```bash
export AWS_REGION=eu-north-1
export STATE_BUCKET=ammonl-db-tf-state
export LOCK_TABLE=ammonl-db-tf-locks
export GITHUB_OWNER=ammonlarson
export REPO_NAME=infra-shared-db
export ROLE_NAME=gha-terraform-shared-db
export ACCOUNT_ID=266535567738
export IP_ADDRESS="$(curl -s https://checkip.amazonaws.com)"
```

### 2. Create the state backend

```bash
aws s3api create-bucket \
--bucket $STATE_BUCKET \
--region $AWS_REGION \
--create-bucket-configuration LocationConstraint=$AWS_REGION

aws s3api put-bucket-versioning \
--bucket $STATE_BUCKET \
--versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
--bucket $STATE_BUCKET \
--server-side-encryption-configuration \
'{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
--bucket $STATE_BUCKET \
--public-access-block-configuration \
BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws dynamodb create-table \
--table-name $LOCK_TABLE \
--attribute-definitions AttributeName=LockID,AttributeType=S \
--key-schema AttributeName=LockID,KeyType=HASH \
--billing-mode PAY_PER_REQUEST \
--region $AWS_REGION
```

> Note: in `us-east-1`, omit the `--create-bucket-configuration` flag; it's the default region and AWS rejects the constraint.

### 3. Create the GitHub OIDC provider and IAM role

```bash
aws iam create-open-id-connect-provider \
--url https://token.actions.githubusercontent.com \
--client-id-list sts.amazonaws.com \
--thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:${GITHUB_OWNER}/${REPO_NAME}:*"
      }
    }
  }]
}
EOF

aws iam create-role \
--role-name $ROLE_NAME \
--assume-role-policy-document file:///tmp/trust-policy.json

aws iam create-policy \
--policy-name gha-terraform-shared-db-least-privilege \
--policy-document file://policies/gha-terraform-shared-db.json

aws iam attach-role-policy \
--role-name $ROLE_NAME \
--policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/gha-terraform-shared-db-least-privilege

echo "Role ARN: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
```

The policy in `policies/gha-terraform-shared-db.json` is scoped to the actions this repo's Terraform actually performs: the state bucket, lock table, RDS instance and subnet group, the VPC security groups, Secrets Manager entries under `rds/shared/`, the SSM bastion (EC2 instance lifecycle, its `shared-db-bastion` IAM role + instance profile, and the AL2023 AMI SSM parameter), and the `ssm:StartSession` port-forward used to reach RDS from the CI apply workflow. The state-backend, Secrets Manager, and IAM statements pin the bucket, table, and account/region by ARN — edit those if you used different names in step 1.

If CI later fails on a missing AWS API permission, add the specific action to the policy rather than reattaching `PowerUserAccess`.

### 4. Configure the backend

Edit `backend.tf` and fill in:

```hcl
terraform {
  backend "s3" {
    bucket         = "<STATE_BUCKET>"
    key            = "infra-shared-db/terraform.tfstate"
    region         = "<AWS_REGION>"
    dynamodb_table = "<LOCK_TABLE>"
    encrypt        = true
  }
}
```

### 5. Configure the GHA role ARN

Edit `.github/workflows/terraform.yml` and set the `role-to-assume` value to the ARN printed in step 3.

### 6. First Terraform apply

Run from your laptop. Because the `postgresql` provider can only reach the private RDS through the bastion tunnel, the bastion has to exist *before* any `postgresql_role` / `postgresql_database` is created. So the first apply is two phases: bring up the AWS-level resources (RDS and the bastion, plus their security groups and IAM) with a targeted apply that never invokes the Postgres provider, then open the tunnel and apply the rest (the master secret and each project's database/role).

```bash
terraform init

# 1. Create the AWS-level resources only. No postgresql_* resource is targeted,
#    so the provider stays idle and needs no tunnel.
terraform apply \
  -target=aws_db_instance.shared \
  -target=aws_instance.bastion

# 2. Open the tunnel through the new bastion (leave it running).
scripts/db-tunnel.sh   # in a second terminal

# 3. Full apply: creates each project's database/role through the tunnel.
terraform apply
```

The same two-phase sequence migrates an existing **public-RDS** state to this model: phase 1 creates the bastion (and flips `publicly_accessible` to `false`); after the tunnel is up, phase 3 swaps the RDS SG to the bastion source and refreshes the Postgres resources. Every routine apply afterward is just "open the tunnel, `terraform apply`" — see [Operator DB/Terraform access](#operator-dbterraform-access-ssm-tunnel).

## CI/CD

Two workflows:

- **`terraform.yml` — lint gate.** Every PR (and every push to `main`) runs `terraform fmt -check -recursive`, `terraform init`, and `terraform validate`. It never dials RDS. AWS auth is OIDC-only; the role exists so `init` can read the S3 backend.
- **`terraform-apply.yml` — apply via bastion.** A manual `workflow_dispatch` (`plan`/`apply` choice) that opens the SSM tunnel on the runner and runs the chosen action, so CI can refresh `postgresql_role` / `postgresql_database` when appropriate. See [Running plan/apply from CI](#running-planapply-from-ci).

Laptop runs and the CI apply workflow both reach RDS the same way — through the bastion tunnel. The lint gate is the only thing that runs unconditionally on every change.

## Network access caveats

RDS is **private** (`publicly_accessible = false`), so there is no public endpoint and no IP allowlist. The `postgresql` provider reaches Postgres through an SSM port-forward to the always-on bastion (`bastion.tf`); operators use `scripts/db-tunnel.sh`, and the CI apply workflow opens the same tunnel on the runner. The bastion has no inbound SG rules — Session Manager is outbound-only — and gets a public IP solely so its SSM agent can reach the SSM endpoints via the default VPC's internet gateway (cheaper than a NAT gateway or SSM interface VPC endpoints, and it does not expose RDS).

The earlier public-RDS + operator-`/32` model is gone (it was the source of the lockout trap in issue #6). The only inbound paths to RDS now are the bastion SG and the peered Greenspace VPC CIDRs.

## Per-environment projects

Projects with multiple deployment environments (e.g. staging and production) get one shared-db project per environment, named `<project>_<env>`. Each environment gets its own database, role, and secret — never one shared database for both. This keeps environment data fully isolated and lets each environment's password rotate independently.

Currently used by:

- **Greenspace** — `greenspace_staging` (secret `rds/shared/greenspace_staging`) and `greenspace_prod` (secret `rds/shared/greenspace_prod`). Each environment's runtime sets `DB_SECRET_ID` to its own secret ID and is granted IAM access only to that ARN.

The convention is enforced by the project name itself (which becomes the database, role, and secret), so the only place to add or remove a per-environment project is the list in `projects.tf` — same flow as any other project (see [ADDING_A_PROJECT.md](./ADDING_A_PROJECT.md)).

## Greenspace VPC peering (accepter side)

Greenspace's API Lambdas run in private subnets with no NAT, so they can't reach RDS over the internet — and with RDS now private there is no public endpoint to reach anyway. Each Greenspace environment instead opens a same-account VPC peering connection from its VPC to the shared RDS default VPC. Greenspace owns the **requester** side of the peering (created with `auto_accept = true` and `requester.allow_remote_vpc_dns_resolution = true`); this repo owns the **accepter** side, defined in `peering.tf`:

- `data "aws_vpc_peering_connection"` discovers each peering by the `Name` tag Greenspace sets (`greenspace-staging-2026-shared-db-peering`, `greenspace-prod-2026-shared-db-peering`), constrained to active peerings whose accepter VPC is the shared-RDS default VPC.
- `aws_vpc_peering_connection_options` sets `accepter.allow_remote_vpc_dns_resolution = true` so the RDS endpoint resolves to its private IP for queries originating in the peered VPC.
- `aws_route` adds the Greenspace VPC CIDR to the default VPC's main route table via the peering connection.
- The Greenspace VPC CIDRs (`10.0.0.0/16` staging, `10.1.0.0/16` prod) populate a dedicated `ingress` block on `aws_security_group.rds` (`network.tf`) via `[for v in local.greenspace_peering : v.vpc_cidr]`, alongside the separate bastion-SG ingress. AWS treats each `cidr_blocks` entry as a separate ingress rule on the SG, so revoking just the staging CIDR is a one-line edit and a single API call — the prod CIDR stays in place.

To add a third environment, add an entry to the `local.greenspace_peering` map in `peering.tf`. The peering data source, options, route, and the inline SG ingress all read from that map (the SG ingress via `concat(...)` over the map's CIDRs), so a one-line edit picks up everywhere.

**Operator sequencing:** the data source for the peering connection fails to plan until Greenspace has applied. When the two repos move together, apply Greenspace first (which creates the peerings), then apply this repo (which configures the accepter side). This repo's PR can be reviewed and merged at any time — CI's lint gate doesn't dial AWS — but `terraform plan` and `apply` will only succeed after the Greenspace apply lands.

The Greenspace operator needs the shared-RDS default VPC's ID and CIDR to populate `shared_db_vpc_id` / `shared_db_vpc_cidr` in `infra/terraform/environments/{staging,prod}/main.tf`. After this repo's first apply, both are available as Terraform outputs:

```bash
terraform output default_vpc_id
terraform output default_vpc_cidr
```

## Connecting from a project repo

The runtime needs IAM permission to read its own secret. The JSON shape of the secret payload is documented as a stable contract in [`SECRET_SCHEMA.md`](./SECRET_SCHEMA.md) — read it before writing consumer code, and run the [pre-merge verification step](./ADDING_A_PROJECT.md#6-verify-the-live-secret-payload-before-merging) against every environment the consumer targets. Example Python:

```python
import boto3, json, os

secret_id = os.environ["DB_SECRET_ID"]  # e.g. "rds/shared/proj_a"
raw = boto3.client("secretsmanager").get_secret_value(SecretId=secret_id)
c = json.loads(raw["SecretString"])
DATABASE_URL = f"postgresql://{c['username']}:{c['password']}@{c['host']}:{c['port']}/{c['database']}"
```

Minimal IAM policy for the project's runtime role:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "secretsmanager:GetSecretValue",
    "Resource": "arn:aws:secretsmanager:<region>:<account>:secret:rds/shared/proj_a-*"
  }]
}
```

## Operations

> All of these reach Postgres, so open the SSM tunnel first (`scripts/db-tunnel.sh`) — see [Operator DB/Terraform access](#operator-dbterraform-access-ssm-tunnel). The `terraform apply` operations need it because the provider refreshes Postgres state; `pg_dump` needs it because RDS is private.

### Rotate a project's password

```bash
terraform taint 'module.projects["proj_a"].random_password.app'
terraform apply
```

The Secrets Manager secret updates atomically. The project picks up the new value on its next read.

### Rotate the master password

```bash
terraform taint random_password.master
terraform apply
```

This forces a brief RDS modification. Plan during a maintenance window if any project does long-lived connections.

### Take a per-project backup

With the tunnel open (`scripts/db-tunnel.sh`), connect through localhost — RDS has no public endpoint:

```bash
PGPASSWORD=$(aws secretsmanager get-secret-value --secret-id rds/shared/master \
  --query 'SecretString' --output text | jq -r '.password') \
pg_dump -h 127.0.0.1 -p 5432 -U tfadmin -d proj_a -f proj_a.sql
```

RDS automated snapshots also run nightly with 7-day retention.

### Remove a project

See [ADDING_A_PROJECT.md](./ADDING_A_PROJECT.md#removing-a-project).

## Troubleshooting

- **`terraform plan`/`apply` hangs or errors connecting to Postgres (`dial tcp 127.0.0.1:5432: connect: connection refused`, or a timeout).** The SSM tunnel isn't open. Run `scripts/db-tunnel.sh` in another terminal first. See [Operator DB/Terraform access](#operator-dbterraform-access-ssm-tunnel).
- **`scripts/db-tunnel.sh` fails with `no running 'shared-db-bastion' instance found`.** The bastion hasn't been created yet (or was stopped/terminated). On a fresh state, run `terraform apply` once to create it; when migrating an existing state, use the targeted bootstrap apply in [First Terraform apply](#6-first-terraform-apply).
- **`SessionManagerPlugin is not found`.** Install the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) for the `aws` CLI.
- **`terraform plan` errors on `data.aws_vpc_peering_connection.greenspace` with `no matching VPC peering connection found`.** The peering connections in `peering.tf` are created by the Greenspace repo, not this one. Until the Greenspace operator populates `shared_db_vpc_id` in `infra/terraform/environments/{staging,prod}/main.tf` and runs `terraform apply`, the data sources have nothing to find — and that blocks every `terraform plan` in this repo, including unrelated project changes. See [Greenspace VPC peering (accepter side)](#greenspace-vpc-peering-accepter-side).
- **`role already exists` on first apply.** The `postgresql` provider can race during the very first apply when both the database and role are new. Re-run `terraform apply`.
- **`InvalidLocationConstraint` creating the state bucket.** You're in `us-east-1`; drop the `--create-bucket-configuration` flag.
- **GHA can't assume the role.** The trust policy's `sub` condition must match `repo:<owner>/<repo>:*` exactly. Recreate the role's trust policy if the repo was renamed.
