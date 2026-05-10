# Ticket 23: Document shared-db secret payload schema and add a pre-merge verification step

## Analysis

**Current state**

- `modules/project/main.tf` defines the per-project Secrets Manager secret.
  Its `secret_string` is `jsonencode({ host, port, database, username, password })`.
- `rds.tf` defines the master secret with the same five keys (sourced from
  the RDS instance attributes plus the master password).
- The schema is therefore implicit: a reader has to open `modules/project/main.tf`
  (or run `aws secretsmanager get-secret-value` against a live secret) to know
  the field names. There is no `SECRET_SCHEMA.md` and no equivalent section in
  `ADDING_A_PROJECT.md` or `README.md`.
- `ADDING_A_PROJECT.md` step 5 ("Wire the secret into the project") shows a
  Python snippet that consumes `c['username']`, `c['password']`, `c['host']`,
  `c['port']`, `c['database']` but does not document the schema as a contract
  and has no pre-merge verification gate.
- Incident reference: `ammonlarson/greenspace` PRs #346/#348. The Greenspace
  consumer was written against the AWS RDS rotation-Lambda format (key
  `dbname`); the shared-db secret keys it as `database`. Mismatch was caught
  only after deploy.

**Target state**

1. A canonical `SECRET_SCHEMA.md` at the repo root that:
   - Lists every JSON field by name with type, meaning, and an example payload.
   - Marks each field as **stable contract** vs **implementation detail**.
   - Notes whether each field is guaranteed present or optional.
   - Cross-links to `ADDING_A_PROJECT.md` and `modules/project/main.tf`.
2. `ADDING_A_PROJECT.md` updated with:
   - A short "Secret payload" pointer in step 5 referencing `SECRET_SCHEMA.md`.
   - A new pre-merge verification step (between current step 5 and step 6)
     that requires the operator to run `aws secretsmanager get-secret-value
     ... | jq 'keys'` against **every** environment the consumer targets and
     cross-check the returned keys against the field names in their consuming
     code.
3. `README.md` gets a one-line pointer in the "Connecting from a project repo"
   section to `SECRET_SCHEMA.md` so the schema is discoverable from the main
   landing doc as well.
4. Structural enforcement (JSON-Schema, Terraform output, verification script)
   is captured as a follow-up issue per the ticket's "do not need to be
   implemented in the same change" framing.

**Approach**

- **Source of truth for fields:** `modules/project/main.tf`
  (`aws_secretsmanager_secret_version.app.secret_string`) is the single
  authoritative place. Every field listed in `SECRET_SCHEMA.md` must match
  that block exactly. There are no "extra" keys today — the rotation Lambda
  is not configured on these secrets, so the live payload is precisely the
  five keys Terraform writes. Document that explicitly so a reader knows
  not to expect AWS rotation-Lambda fields like `engine` or
  `dbInstanceIdentifier`.
- **Stable contract vs implementation detail:** all five current fields
  (`database`, `host`, `password`, `port`, `username`) are part of the stable
  contract — the consumer needs every one to build a connection string. There
  is no "implementation detail" field today, but the doc should call out that
  any future additions (e.g. `dbInstanceIdentifier` if AWS-managed rotation is
  ever turned on) would be **optional/non-contract** unless explicitly added
  to the stable list. This pre-empts the same trap from recurring.
- **Verification snippet:** put the exact `aws secretsmanager get-secret-value
  ... | jq 'keys'` command into `ADDING_A_PROJECT.md` and into
  `SECRET_SCHEMA.md`, and explicitly note that staging and prod must be
  checked separately (the incident showed both could diverge).
- **Where to put the new step in `ADDING_A_PROJECT.md`:** the ticket says "in
  the section that walks the consumer through wiring up their runtime", which
  is current step 5. Insert a new step 6 ("Verify the live secret payload")
  between the existing step 5 ("Wire the secret into the project") and the
  existing step 6 ("Run migrations") — and renumber. The step has to fire
  *before* the consumer PR merges, so it sits in the consumer-wiring block,
  not in the migrations block.
- **Cross-linking:** both docs link to each other and to
  `modules/project/main.tf:36-49` (the resource block that writes the
  payload), so a reader landing on either page can hop to the other.
- **Follow-up issue for structural enforcement:** open after the PR lands so
  the link is captured. Title: "Add structural enforcement of shared-db
  secret schema" — covering the JSON-Schema/Terraform-output/script options
  the ticket lists. Mark this as a follow-up in the PR body.

**No code changes**

This is a docs-only PR. `modules/project/main.tf`, `rds.tf`, `projects.tf`,
and CI are not modified. `terraform fmt -check -recursive` and `terraform
validate` still pass because no `.tf` files change. The pre-commit hook will
still run `tflint --recursive` and the format/validate gates against the
unchanged Terraform; no AWS calls are required.

## Task Checklist

- [x] Read ticket; add labels (`agent active`, `claude`).
- [x] Create planning document.
- [x] Branch `claude/ticket-23-task-w3nmA` already exists and is checked out.
- [ ] Create `SECRET_SCHEMA.md` at the repo root.
- [ ] Update `ADDING_A_PROJECT.md`: add a "Secret payload" pointer in the
      wiring step and insert a new "Verify the live secret payload" step
      with the `jq 'keys'` command.
- [ ] Update `README.md` "Connecting from a project repo" with a one-line
      pointer to `SECRET_SCHEMA.md`.
- [ ] Run `terraform fmt -check -recursive` (no-op for docs, sanity check).
- [ ] Commit on `claude/ticket-23-task-w3nmA`; push.
- [ ] Open PR; reference issue #23; mention follow-up for structural
      enforcement.
- [ ] Run pr-reviewer agent; address feedback.
- [ ] Open follow-up issue for structural enforcement; link from PR.
- [ ] Add `ammonl` reviewer; comment on ticket with implementation summary;
      remove `agent active` label.

## Implementation Summary

- Files touched:
  - `SECRET_SCHEMA.md` — new file, canonical schema doc.
  - `ADDING_A_PROJECT.md` — add wiring-step pointer and a new pre-merge
    verification step; renumber subsequent steps.
  - `README.md` — one-line pointer to `SECRET_SCHEMA.md`.
- No `.tf` changes, no IAM changes, no CI changes.
- Tests: N/A (docs only; no test suite in this repo).
- CI gates: unchanged. `fmt -check`/`init`/`validate` continue to pass.
- Follow-up: separate issue tracking optional structural enforcement
  (JSON-Schema / Terraform output / `scripts/verify-secret-shape.sh`).
