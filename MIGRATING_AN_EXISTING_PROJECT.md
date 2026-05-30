# Migrating an existing consumer repo onto shared-db

This is the runbook for moving a repo that **already runs on its own dedicated
database** over to `infra-shared-db`. It is deliberately separate from
[`ADDING_A_PROJECT.md`](./ADDING_A_PROJECT.md), which is the greenfield happy
path for a project that has no prior database to retire.

Use this guide when the consumer repo must:

1. provision shared-db databases + secrets for staging **and** prod,
2. add requester-side VPC peering and switch its runtime to read the shared-db
   secret,
3. cut traffic over (staging first, then prod),
4. validate the new path end to end, and only then
5. tear down its old dedicated DB infrastructure and stale docs.

The sequence and the gotchas below were learned from the Greenspace migration
(`ammonlarson/greenspace` #340 cutover, PR #346 runtime switch to per-environment
`DB_SECRET_ID`, PR #348 `database` vs `dbname` hotfix, #347 dedicated-RDS cleanup).
Follow it almost mechanically; deviate only where your repo genuinely differs.

> **The whole plan/apply path is operator-side, not CI-side.** CI here is only a
> lint gate (`fmt -check` + `init` + `validate`); it never dials RDS and never
> applies. Every `terraform plan`/`apply` step below runs from an operator
> laptop with the SSM tunnel open (`scripts/db-tunnel.sh`), or via the manual
> `Terraform apply (via SSM bastion)` workflow. See
> [Operator DB/Terraform access](./README.md#operator-dbterraform-access-ssm-tunnel).

---

## Two-repo mental model

Two repos move together, and the order matters because each side has a data
source or config value that does not resolve until the other side has applied:

| Repo | Owns | Blocks on |
| --- | --- | --- |
| **`infra-shared-db`** (this repo) | the per-environment databases/roles/secrets, and the **accepter** side of VPC peering | accepter-side peering can't plan until the consumer has created the **requester** side |
| **consumer repo** (e.g. Greenspace) | its runtime, the **requester** side of VPC peering, and (until cutover) its old dedicated DB | needs `default_vpc_id` / `default_vpc_cidr` outputs from this repo, and live secrets to point its runtime at |

This circularity is why the sequence interleaves the two repos rather than
finishing one and then the other.

---

## End-to-end sequence

Each step says **which repo** it happens in and **who/what** runs it.

### Phase A — Provision shared-db projects (this repo)

1. **Add per-environment projects to `projects.tf`** (this repo).
   Per-environment projects are **separate projects with separate secrets** —
   `<project>_staging` and `<project>_prod` — never one shared secret with an
   environment switch. See
   [Per-environment projects](./README.md#per-environment-projects).

   ```hcl
   locals {
     projects = [
       # ...existing...
       "myapp_staging",
       "myapp_prod",
     ]
   }
   ```

2. **Plan and apply locally** (operator laptop, tunnel open). Open a PR for the
   `projects.tf` change, then get the authoritative diff from your laptop —
   CI's lint gate produces no plan:

   ```bash
   scripts/db-tunnel.sh        # separate terminal, leave running
   terraform plan
   ```

   ☑️ **Checkpoint:** the plan shows **only additions** for the two new projects
   (`random_password`, `postgresql_role`, `postgresql_database`,
   `aws_secretsmanager_secret`, `aws_secretsmanager_secret_version` — per
   environment). If anything is being **destroyed**, stop and investigate before
   applying. See [Gotchas](#known-gotchas) for the SG/ingress diff to watch for.

   ```bash
   terraform apply
   ```

   The two secrets now exist at `rds/shared/myapp_staging` and
   `rds/shared/myapp_prod`.

3. **Capture the VPC outputs for the consumer** (this repo, after apply). The
   consumer's requester-side peering needs the shared-RDS VPC ID and CIDR:

   ```bash
   terraform output default_vpc_id
   terraform output default_vpc_cidr
   ```

   Hand these to the consumer operator. See
   [Greenspace VPC peering](./README.md#greenspace-vpc-peering-accepter-side).

### Phase B — Consumer adds peering + reads secrets (consumer repo)

4. **Consumer adds requester-side peering** (consumer repo) using the VPC
   id/cidr from step 3, one peering per environment, with a stable `Name` tag
   this repo can discover (e.g. `myapp-staging-2026-shared-db-peering`). The
   consumer creates the peering with `auto_accept = true` and
   `requester.allow_remote_vpc_dns_resolution = true`, then applies — **the
   consumer applies its requester side before this repo can configure the
   accepter side** (see step 6).

5. **Consumer points its runtime at the secret** (consumer repo), behind config
   so traffic doesn't cut over yet. Set `DB_SECRET_ID` **per environment** to the
   matching secret (`rds/shared/myapp_staging` / `rds/shared/myapp_prod`) and read
   the payload at startup. The secret keys are a fixed contract — see
   [`SECRET_SCHEMA.md`](./SECRET_SCHEMA.md):

   ```python
   import boto3, json, os

   raw = boto3.client("secretsmanager").get_secret_value(
       SecretId=os.environ["DB_SECRET_ID"]
   )
   c = json.loads(raw["SecretString"])
   DATABASE_URL = (
       f"postgresql://{c['username']}:{c['password']}@{c['host']}:{c['port']}/{c['database']}"
   )
   ```

   Read `database`, **not** `dbname`. Grant the runtime IAM role
   `secretsmanager:GetSecretValue` on **only its own** secret ARN(s) — never the
   master secret, never another project's secret.

### Phase C — Accepter peering + validate (this repo, then consumer)

6. **Apply accepter-side peering** (this repo). The
   `data "aws_vpc_peering_connection"` in [`peering.tf`](./peering.tf) discovers
   the consumer's peerings **by tag** and will not plan until step 4 has landed.
   If the consumer also lives in the `greenspace_peering`-style map, add the new
   environments there; for a different consumer, add an analogous map/entries.
   Then, with the tunnel open:

   ```bash
   terraform plan    # succeeds only after the consumer's requester apply (step 4)
   terraform apply
   ```

7. **Verify the live secret payload for *each* environment** before merging the
   consumer's runtime change. Run the verifier once per environment — staging and
   prod can diverge, so one check is not enough:

   ```bash
   scripts/verify-secret-shape.sh rds/shared/myapp_staging eu-north-1
   scripts/verify-secret-shape.sh rds/shared/myapp_prod    eu-north-1
   ```

   ☑️ **Checkpoint:** both pass (every required field present with the right JSON
   type). If either fails, **do not merge the consumer** — fix the consumer to
   read the contract names first. This is the exact step whose absence caused the
   Greenspace `dbname` incident.

### Phase D — Cut over (consumer repo, staging → prod)

8. **Cut staging over first** (consumer repo). Flip staging traffic to the
   shared-db `DATABASE_URL`, run the consumer's normal migrations against the new
   database, and validate staging health end to end (app boots, connects, reads
   `database`, queries succeed over the peering link).

   ☑️ **Checkpoint:** staging is healthy on shared-db **before you touch prod.**

9. **Cut prod over** (consumer repo) only after staging is proven. Same steps,
   prod secret and database.

### Phase E — Retire the old dedicated DB (consumer repo)

10. **After stabilization**, remove the consumer's legacy dedicated-DB
    infrastructure. See [Post-cutover cleanup](#post-cutover-cleanup) — this is a
    consumer-repo change; nothing about it touches `infra-shared-db`.

---

## Operator-owned validation checkpoints

Collected here so they're easy to tick off. All of these are operator actions —
none are enforced by CI.

- [ ] **This repo's plan shows only the intended additions** for the new
      per-environment projects (step 2). No unexpected destroys, no SG ingress
      removals (see [Gotchas](#known-gotchas)).
- [ ] **Live secret payload verified for *each* environment** (`_staging` **and**
      `_prod`) against [`schemas/secret.schema.json`](./schemas/secret.schema.json)
      via `scripts/verify-secret-shape.sh`, before merging consumer runtime
      changes (step 7).
- [ ] **Consumer reads `database`, not `dbname`** (step 5 / step 7).
- [ ] **Consumer's runtime IAM is scoped to its own secret ARN(s) only** — not the
      master secret, not other projects.
- [ ] **Staging is healthy on shared-db before prod is touched** (step 8).
- [ ] **The consumer cleanup plan destroys only legacy dedicated-DB resources**
      (Phase E) — diff it carefully.
- [ ] **A final snapshot / retention decision is made before any destroy** (see
      below).

### Final-snapshot / retention decision

Before destroying the old dedicated DB, decide explicitly whether you need a
retained copy of its data:

- If you might want the data later, take a `pg_dump` (or keep a final RDS
  snapshot) **before** the destroy — a destroyed DB is gone.
- If the dedicated RDS sets `skip_final_snapshot = false` /
  `final_snapshot_identifier`, the destroy will produce a final snapshot anyway;
  confirm that's what you want and that `deletion_protection` is handled.
- Record the decision in the cleanup PR so it isn't a silent assumption.

---

## Known gotchas

Called out explicitly because each one has bitten a real migration:

- **plan/apply are operator-side, not CI-side.** CI is a lint gate only
  (`fmt`/`init`/`validate`); it never dials RDS and never applies. Anything that
  must reach Postgres (every project add, every peering apply, every verify
  against a live secret) runs from a laptop with the tunnel open, or via the
  manual apply workflow. Don't expect merging a PR to change any infrastructure.
- **Inspect every security-group / ingress change in the plan.** A project-list
  change should not touch `aws_security_group.rds`. The RDS SG ingress is derived
  from the bastion SG plus the peered-VPC CIDRs (`network.tf` /
  [`peering.tf`](./peering.tf)); a stray diff that *removes* an ingress means
  something upstream changed. (Historical note: the old operator-IP `/32`
  allowlist that could be dropped by running without a populated
  `terraform.tfvars` is **gone** — the bastion model replaced it, and
  `terraform.tfvars` is now only an optional `postgres_port` override. There is no
  operator CIDR to lose anymore, but the habit of reading the SG diff stays.)
- **Per-environment projects are separate projects/secrets.** `<project>_staging`
  and `<project>_prod` are two independent databases, roles, and secrets — not one
  shared secret plus a runtime environment switch. Each rotates independently and
  each is verified independently.
- **The secret contract uses `database`, not `dbname`.** The AWS-managed RDS
  rotation-Lambda shape (`dbname`, `engine`, …) is **not** what these secrets use.
  A consumer reading `dbname` deserializes fine and then fails at connect time.
  This is the Greenspace PR #348 hotfix; see
  [`SECRET_SCHEMA.md`](./SECRET_SCHEMA.md).
- **Accepter-side peering can't plan until the consumer's requester side
  exists.** The `data "aws_vpc_peering_connection"` in [`peering.tf`](./peering.tf)
  discovers peerings by tag; until the consumer has applied its requester side,
  the data source finds nothing — and that blocks **every** `terraform plan` in
  this repo, including unrelated project changes. Apply the consumer (requester)
  first, then this repo (accepter). See the
  [troubleshooting entry](./README.md#troubleshooting) for
  `no matching VPC peering connection found`.

---

## Post-cutover cleanup

Once both environments are stable on shared-db (give it long enough to trust —
at least a full deploy/restart cycle and any nightly jobs), retire the old
dedicated DB **in the consumer repo**. This guide's repo (`infra-shared-db`)
needs no changes in this phase.

What belongs in the consumer cleanup:

- **Old dedicated RDS resources** — the instance, its subnet group, parameter
  groups, and the security groups that existed only for it (Greenspace #347).
- **Legacy DB secrets / outputs** — any old connection secret, plus Terraform
  outputs or SSM params that exported the dedicated DB's endpoint/credentials.
- **Old runtime assumptions** — env vars, defaults, and connection code paths
  that pointed at the dedicated DB rather than `DB_SECRET_ID`.
- **Docs / runbooks** — anything in the consumer repo that still describes the
  dedicated DB as the live database. Update or delete it so the next reader
  isn't misled.

Before considering cleanup complete:

- [ ] The cleanup `terraform plan` destroys **only** the legacy dedicated-DB
      resources — nothing shared, nothing still in use.
- [ ] A final snapshot / `pg_dump` was taken (or consciously declined — see
      [the retention decision](#final-snapshot--retention-decision)).
- [ ] No remaining code or config references the old DB endpoint/secret.
- [ ] Consumer docs/runbooks no longer present the dedicated DB as active.

---

## Downstream-consumer handoff checklist

Drop this into the **consumer repo's** migration issue/PR so its operator can
drive their side. (`infra-shared-db` owns the project list, the secrets, and the
accepter-side peering; the consumer owns everything below.)

```markdown
## Migrate <repo> onto infra-shared-db

Shared-db side (coordinate with the infra-shared-db operator):
- [ ] infra-shared-db has added `<project>_staging` and `<project>_prod` to
      projects.tf and applied (secrets exist at rds/shared/<project>_<env>).
- [ ] Got `default_vpc_id` and `default_vpc_cidr` from infra-shared-db outputs.

This repo (consumer):
- [ ] Added requester-side VPC peering per environment, tagged
      `<project>-<env>-<year>-shared-db-peering`, auto_accept = true,
      requester.allow_remote_vpc_dns_resolution = true; applied.
- [ ] Set DB_SECRET_ID per environment (rds/shared/<project>_staging /
      rds/shared/<project>_prod) — separate secrets, not one switched secret.
- [ ] Runtime builds DATABASE_URL from the secret and reads `database`
      (NOT `dbname`), plus host/port/username/password.
- [ ] Runtime IAM role can GetSecretValue on ONLY its own secret ARN(s).

Validation (operator, before cutover):
- [ ] infra-shared-db operator confirmed accepter-side peering applied
      (it can only plan after this repo's requester apply lands).
- [ ] verify-secret-shape.sh passed for staging AND prod.
- [ ] Staging cut over and healthy on shared-db before touching prod.
- [ ] Prod cut over and healthy.

Cleanup (after stabilization):
- [ ] Final snapshot / pg_dump taken (or consciously declined).
- [ ] Old dedicated RDS + subnet/parameter/security groups destroyed
      (plan touches ONLY legacy dedicated-db resources).
- [ ] Legacy DB secrets/outputs and old runtime assumptions removed.
- [ ] Consumer docs/runbooks no longer describe the dedicated DB as active.
```

---

## Related

- [`ADDING_A_PROJECT.md`](./ADDING_A_PROJECT.md) — greenfield project add (no
  prior DB to retire); the per-project mechanics this guide builds on.
- [`SECRET_SCHEMA.md`](./SECRET_SCHEMA.md) — the secret payload contract
  (`database` not `dbname`) and the verification step.
- [`README.md`](./README.md) — operator tunnel access, per-environment projects,
  accepter-side peering, and troubleshooting.
