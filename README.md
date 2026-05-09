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
- `gh` CLI (optional, for repo creation)

## One-time bootstrap

A few resources can't be managed by Terraform itself (chicken-and-egg with the state backend, plus the OIDC trust). Create them once by hand.

### 1. Set environment variables

Pick names and a region. These are referenced throughout this section.

```bash
export AWS_REGION=eu-west-1
export STATE_BUCKET=<your-unique-name>-tf-state
export LOCK_TABLE=<your-unique-name>-tf-locks
export GITHUB_OWNER=<your-github-user-or-org>
export REPO_NAME=infra-shared-db
export ROLE_NAME=gha-terraform-shared-db
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
terraform init
terraform plan -var='allowed_ingress_cidrs=["<your-ip>/32"]'
terraform apply -var='allowed_ingress_cidrs=["<your-ip>/32"]'
```

Set `allowed_ingress_cidrs` to whichever IPs need direct DB access. Add the egress IP ranges of any external app hosts (e.g., Vercel) here too. Persist the value by putting it in a `terraform.tfvars` file (gitignored) or in a workspace variable.

## CI/CD

- Every PR runs `terraform plan` and posts the diff as a comment.
- Merging to `main` runs `terraform apply` after manual approval via the `production` GitHub environment.
- AWS auth is OIDC-only; no access keys are stored in GitHub.

## Network access caveats

The `postgresql` provider needs network reachability to RDS to manage databases and roles. Two paths:

- **Public RDS, restricted SG (default).** `publicly_accessible = true` with a security group locked to `var.allowed_ingress_cidrs`. The SG is the firewall.
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

- **`terraform plan` from CI errors connecting to Postgres.** The GHA runner's egress IP isn't in `allowed_ingress_cidrs`. Either add the GitHub-published ranges (broad) or split this repo into two root modules: AWS-level (CI-applied) and Postgres-level (locally applied).
- **`role already exists` on first apply.** The `postgresql` provider can race during the very first apply when both the database and role are new. Re-run `terraform apply`.
- **`InvalidLocationConstraint` creating the state bucket.** You're in `us-east-1`; drop the `--create-bucket-configuration` flag.
- **GHA can't assume the role.** The trust policy's `sub` condition must match `repo:<owner>/<repo>:*` exactly. Recreate the role's trust policy if the repo was renamed.
