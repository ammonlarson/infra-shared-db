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
├── rds.tf
├── projects.tf
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
- A local `terraform.tfvars` containing your operator IP (see [Operator IP and `terraform.tfvars`](#operator-ip-and-terraformtfvars) below). **Required for any local `terraform plan` or `apply` that touches Postgres-level resources.**

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
<type>(<optional-scope>): <summary>
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
2. `terraform apply` from your laptop. The plan should be a one-line `~ ingress` diff on `aws_security_group.rds`.

### Why GitHub Actions can't apply Postgres-level changes

CI authenticates to AWS over OIDC, but the GHA runner's egress IP isn't in your allowlist (only your operator IP is). The `cyrilgdn/postgresql` provider needs to reach RDS to refresh or create `postgresql_role` / `postgresql_database` resources, and that's blocked.

- **While `local.projects` is empty,** there are no `postgresql_*` resources in state and CI can `plan` / `apply` AWS-level changes (RDS instance, security group, master secret) without ever dialling Postgres.
- **Once any project exists in state,** every CI run has to refresh those Postgres-level resources, so `plan` and `apply` will fail — even on PRs that touch only AWS-level resources. From that point on, all `terraform apply` runs come from your laptop with `terraform.tfvars` populated. See [ADDING_A_PROJECT.md](./ADDING_A_PROJECT.md) for the project-change flow.

If you want CI to handle project provisioning end-to-end, see option (B) or (C) in issue #6 — both lift this constraint, at the cost of more infra.

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

- Every PR runs `terraform plan` and posts the diff as a comment.
- Merging to `main` runs `terraform apply` after manual approval via the `production` GitHub environment.
- AWS auth is OIDC-only; no access keys are stored in GitHub.
- **CI is only fully usable while no projects exist in state.** Once any project has been provisioned, the `cyrilgdn/postgresql` provider has to refresh `postgresql_role` / `postgresql_database` on every CI `plan` and `apply` — and the GHA runner's IP isn't in `allowed_ingress_cidrs`, so refresh will fail. Both AWS-level and Postgres-level changes then need a local `terraform apply`. See [ADDING_A_PROJECT.md](./ADDING_A_PROJECT.md) for the project-change flow; for AWS-only diffs, applying locally with the operator IP populated is the same workflow.

## Network access caveats

The `postgresql` provider needs network reachability to RDS to manage databases and roles. Two paths:

- **Public RDS, restricted SG (default).** `publicly_accessible = true` with a security group locked to `var.allowed_ingress_cidrs`. The SG is the firewall. Today the allowlist holds only the operator's residential `/32` (see [Operator IP and `terraform.tfvars`](#operator-ip-and-terraformtfvars)), which means *every* Terraform run that has to refresh a `postgresql_*` resource has to come from the operator's laptop — including AWS-only diffs once any project exists in state. CI is fine while `local.projects` is empty.
- **Private RDS.** Set `publicly_accessible = false` and run Postgres-level applies from inside the VPC (bastion, SSM tunnel, or self-hosted GHA runner). AWS-level applies can still run from CI.

For a single-operator side-project setup, public + restricted SG is simpler and equally safe. Switch to private only if compliance requires it.

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

- **`terraform plan` from CI errors connecting to Postgres.** Expected once any project exists in state — refreshing `postgresql_*` resources requires reaching RDS, and the GHA runner's egress IP isn't in `allowed_ingress_cidrs`. Run `terraform plan` and `terraform apply` locally instead; see [ADDING_A_PROJECT.md](./ADDING_A_PROJECT.md). CI plan only works cleanly while `local.projects` is empty.
- **`terraform apply` proposes removing your CIDR from `aws_security_group.rds`.** You ran without `terraform.tfvars` (or the file is missing/empty). Don't apply — populate the file first. See [Operator IP and `terraform.tfvars`](#operator-ip-and-terraformtfvars).
- **`role already exists` on first apply.** The `postgresql` provider can race during the very first apply when both the database and role are new. Re-run `terraform apply`.
- **`InvalidLocationConstraint` creating the state bucket.** You're in `us-east-1`; drop the `--create-bucket-configuration` flag.
- **GHA can't assume the role.** The trust policy's `sub` condition must match `repo:<owner>/<repo>:*` exactly. Recreate the role's trust policy if the repo was renamed.
