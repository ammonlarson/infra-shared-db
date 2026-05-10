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
- `terraform` >= 1.6
- [`tflint`](https://github.com/terraform-linters/tflint) (used by the local pre-commit hook)
- `gh` CLI (optional, for repo creation)
- A local `terraform.tfvars` containing your operator IP (see [Operator IP and `terraform.tfvars`](#operator-ip-and-terraformtfvars) below). **Required for every `terraform plan` and `apply` — those run on your laptop, not in CI.**

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
  credentials, network reachability to RDS, and the operator IP in
  `allowed_ingress_cidrs`. CI runs `plan` on every PR.

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

## Operator IP and `terraform.tfvars`

> **Read this before your first `terraform plan` or `apply`.** Skipping it will silently propose removing your own ingress CIDR.

The RDS instance is `publicly_accessible = true`, gated only by a security group whose ingress list comes from `var.allowed_ingress_cidrs`. The variable defaults to `[]` (no ingress). That default is deliberate — committing a residential IP to the tracked source would be worse — but it means **any `terraform apply` that runs without the operator's `/32` will plan to remove the existing CIDR**, locking everyone (including you) out of the database.

The fix is to persist the value in a gitignored `terraform.tfvars`:

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars and replace the placeholder with your /32
terraform plan
terraform apply
```

`terraform.tfvars` is matched by `.gitignore` (`*.tfvars`); `terraform.tfvars.example` is whitelisted (`!*.tfvars.example`) and lives in the repo as a template.

When your ISP rotates your IP:

1. Update `terraform.tfvars` with the new `/32`.
2. `terraform apply` from your laptop. The plan should be a one-line `~ ingress` diff on `aws_security_group.rds` — only the `cidr_blocks` list changes.

### Why GitHub Actions doesn't run `terraform apply`

CI is a lint gate only. It runs `terraform fmt -check`, `terraform init`, and `terraform validate` — nothing that has to dial RDS. The reason `apply` (and `plan`) aren't in CI: only the operator's residential `/32` is in `allowed_ingress_cidrs`, the GHA runner's egress IP is not, so the `cyrilgdn/postgresql` provider can't refresh `postgresql_role` / `postgresql_database` from CI as soon as any project exists in state. Every `terraform plan` / `apply` runs from your laptop with `terraform.tfvars` populated. See [ADDING_A_PROJECT.md](./ADDING_A_PROJECT.md) for the project-change flow; AWS-only diffs use the same workflow.

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

The policy in `policies/gha-terraform-shared-db.json` is scoped to the actions this repo's Terraform actually performs: the state bucket, lock table, RDS instance and subnet group, the VPC security group, and Secrets Manager entries under `rds/shared/`. The state-backend and Secrets Manager statements pin the bucket, table, and account/region by ARN — edit those if you used different names in step 1.

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

Run from your laptop. The first apply creates the RDS instance and the master secret.

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set allowed_ingress_cidrs to your /32
terraform init
terraform plan
terraform apply
```

`terraform.tfvars` is gitignored — see [Operator IP and `terraform.tfvars`](#operator-ip-and-terraformtfvars) for the full workflow and why this matters for every subsequent apply.

## CI/CD

CI is a lint gate, not a deployer. Every PR (and every push to `main`) runs `terraform fmt -check -recursive`, `terraform init`, and `terraform validate`. AWS auth is OIDC-only; the role exists so `init` can read the S3 backend.

`terraform plan` and `terraform apply` are operator-side, not CI-side — see [Why GitHub Actions doesn't run `terraform apply`](#why-github-actions-doesnt-run-terraform-apply).

## Network access caveats

The `postgresql` provider needs network reachability to RDS to manage databases and roles. Two paths:

- **Public RDS, restricted SG (default).** `publicly_accessible = true` with a security group locked to `var.allowed_ingress_cidrs`. The SG is the firewall. Today the allowlist holds only the operator's residential `/32` (see [Operator IP and `terraform.tfvars`](#operator-ip-and-terraformtfvars)), which is why all `terraform plan` and `apply` runs are operator-side — CI couldn't refresh Postgres-level resources from the GHA runner's IP.
- **Private RDS.** Set `publicly_accessible = false` and run Postgres-level applies from inside the VPC (bastion, SSM tunnel, or self-hosted GHA runner).

For a single-operator side-project setup, public + restricted SG is simpler and equally safe. Switch to private only if compliance requires it.

## Per-environment projects

Projects with multiple deployment environments (e.g. staging and production) get one shared-db project per environment, named `<project>_<env>`. Each environment gets its own database, role, and secret — never one shared database for both. This keeps environment data fully isolated and lets each environment's password rotate independently.

Currently used by:

- **Greenspace** — `greenspace_staging` (secret `rds/shared/greenspace_staging`) and `greenspace_prod` (secret `rds/shared/greenspace_prod`). Each environment's runtime sets `DB_SECRET_ID` to its own secret ID and is granted IAM access only to that ARN.

The convention is enforced by the project name itself (which becomes the database, role, and secret), so the only place to add or remove a per-environment project is the list in `projects.tf` — same flow as any other project (see [ADDING_A_PROJECT.md](./ADDING_A_PROJECT.md)).

## Greenspace VPC peering (accepter side)

Greenspace's API Lambdas run in private subnets with no NAT, so they can't reach the public RDS endpoint over the internet. Each Greenspace environment instead opens a same-account VPC peering connection from its VPC to the shared RDS default VPC. Greenspace owns the **requester** side of the peering (created with `auto_accept = true` and `requester.allow_remote_vpc_dns_resolution = true`); this repo owns the **accepter** side, defined in `peering.tf`:

- `data "aws_vpc_peering_connection"` discovers each peering by the `Name` tag Greenspace sets (`greenspace-staging-2026-shared-db-peering`, `greenspace-prod-2026-shared-db-peering`), constrained to active peerings whose accepter VPC is the shared-RDS default VPC.
- `aws_vpc_peering_connection_options` sets `accepter.allow_remote_vpc_dns_resolution = true` so the public RDS endpoint resolves to the RDS private IP for queries originating in the peered VPC.
- `aws_route` adds the Greenspace VPC CIDR to the default VPC's main route table via the peering connection.
- The Greenspace VPC CIDRs (`10.0.0.0/16` staging, `10.1.0.0/16` prod) are added to the inline `ingress` block on `aws_security_group.rds` (`network.tf`) via `concat(var.allowed_ingress_cidrs, [for v in local.greenspace_peering : v.vpc_cidr])`. AWS treats each `cidr_blocks` entry as a separate ingress rule on the SG, so revoking just the staging CIDR is a one-line edit and a single API call — the prod CIDR and operator `/32`s stay in place.

To add a third environment, add an entry to the `local.greenspace_peering` map in `peering.tf`. The peering data source, options, route, and the inline SG ingress all read from that map (the SG ingress via `concat(...)` over the map's CIDRs), so a one-line edit picks up everywhere.

**Operator sequencing:** the data source for the peering connection fails to plan until Greenspace has applied. When the two repos move together, apply Greenspace first (which creates the peerings), then apply this repo (which configures the accepter side). This repo's PR can be reviewed and merged at any time — CI's lint gate doesn't dial AWS — but `terraform plan` and `apply` will only succeed after the Greenspace apply lands.

The Greenspace operator needs the shared-RDS default VPC's ID and CIDR to populate `shared_db_vpc_id` / `shared_db_vpc_cidr` in `infra/terraform/environments/{staging,prod}/main.tf`. After this repo's first apply, both are available as Terraform outputs:

```bash
terraform output default_vpc_id
terraform output default_vpc_cidr
```

## Connecting from a project repo

The runtime needs IAM permission to read its own secret. Example Python:

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

```bash
HOST=$(aws secretsmanager get-secret-value --secret-id rds/shared/master \
  --query 'SecretString' --output text | jq -r '.host')
PGPASSWORD=$(aws secretsmanager get-secret-value --secret-id rds/shared/master \
  --query 'SecretString' --output text | jq -r '.password') \
pg_dump -h $HOST -U tfadmin -d proj_a -f proj_a.sql
```

RDS automated snapshots also run nightly with 7-day retention.

### Remove a project

See [ADDING_A_PROJECT.md](./ADDING_A_PROJECT.md#removing-a-project).

## Troubleshooting

- **`terraform apply` proposes removing your CIDR from `aws_security_group.rds`.** You ran without `terraform.tfvars` (or the file is missing/empty). Don't apply — populate the file first. See [Operator IP and `terraform.tfvars`](#operator-ip-and-terraformtfvars).
- **`terraform plan` errors on `data.aws_vpc_peering_connection.greenspace` with `no matching VPC peering connection found`.** The peering connections in `peering.tf` are created by the Greenspace repo, not this one. Until the Greenspace operator populates `shared_db_vpc_id` in `infra/terraform/environments/{staging,prod}/main.tf` and runs `terraform apply`, the data sources have nothing to find — and that blocks every `terraform plan` in this repo, including unrelated project changes. See [Greenspace VPC peering (accepter side)](#greenspace-vpc-peering-accepter-side).
- **`role already exists` on first apply.** The `postgresql` provider can race during the very first apply when both the database and role are new. Re-run `terraform apply`.
- **`InvalidLocationConstraint` creating the state bucket.** You're in `us-east-1`; drop the `--create-bucket-configuration` flag.
- **GHA can't assume the role.** The trust policy's `sub` condition must match `repo:<owner>/<repo>:*` exactly. Recreate the role's trust policy if the repo was renamed.
