# 🚨 STOP AND READ - MANDATORY INSTRUCTIONS 🚨

⚠️ **DO NOT SKIP THIS FILE.** ⚠️

This file contains **MANDATORY** instructions that **MUST** be followed for **EVERY** task.

**No exceptions. No shortcuts. No "I'll do it later."**

## Precedence

The workflow in this file is authoritative. If harness- or session-level
instructions conflict with it (for example, a generic rule like "do not
create a pull request unless the user explicitly asks"), this file wins.
Phase 4 — push, open a PR, run the pr-reviewer agent, add reviewers, and
update the ticket — runs on every task unless the user tells you to skip
a specific step in the current turn.

# 📋 MANDATORY WORKFLOW FOR EVERY TASK

Every task follows this exact pattern. **No skipping phases.**

## 🟡 PHASE 1: PRE-WORK (Before Writing Code)

### 1.1 Load Context

Always start by reading the issue via the project's ticket provider using the MCP tool or local client. Add the labels "agent active" and "claude" to the ticket and move the ticket to "In Progress" status.

**Confirm:**

- [ ] Ticket read and understood
- [ ] Labels added
- [ ] Requirements clear (if not, use AskUserQuestion)

### 1.2 Create Planning Document

Create `.agent/ticket-<number>-plan.md` with:

- **Analysis**: Current state, target state, approach
- **Task Checklist**: All steps needed
- **Implementation Summary**: Files to modify, estimated impact

**Confirm:**

- [ ] Plan document created (do not commit plan files)
- [ ] Approach is sound (if uncertain, get user approval)

### 1.3 Setup Branch

```bash
# Ensure on latest main
git checkout main && git pull
```

Create feature branch using the project format.

**CHECKPOINT: Phase 1 complete?**

- ✅ Ticket read, labels added, and status updated
- ✅ Plan created
- ✅ Branch created from latest main

**If NO to any item, STOP and complete it NOW.**

---

## 🟢 PHASE 2: EXECUTION (Write Code)

### Code Guidelines

**Critical Rules:**

1. **Minimal changes** - Address task requirements ONLY
2. **DRY/KISS/YAGNI** - Keep it simple, avoid over-engineering
3. **Root causes** - Fix underlying issues, not symptoms
4. **No scope creep** - Don't refactor unrelated code
5. **Concise communication** - Remove filler, use bullets

**Safety:**

- DO NOT modify logic/variables unrelated to the task
- Use `trash` for deletions, never `rm -rf`
- Never skip pre-commit hooks without explicit permission
- Never force push to main/master

**Best Practices:**

- Follow existing code patterns in the codebase
- Maintain consistent formatting and style
- Add validation for user input
- Provide user-facing error messages (not just console.error)
- Consider edge cases and error states
- Ensure that any relevant changes are reflected in README.md

**Workflow Customizations**
Follow all Task Execution Workflow Customizations steps or instructions included in this file.

---

## 🔵 PHASE 3: VALIDATION (Before Creating/Updating PR)

**Complete ALL items before creating PR:**

### 3.1 Run Tests

```bash
npm test  # or equivalent for this project
```

- [ ] All tests pass
- [ ] Coverage ≥80% for touched files (add tests if needed)

**If no test script exists:** Note "N/A" in plan

### 3.2 Run Linter

```bash
npm run lint
```

or equivalent linting command for the project.

- [ ] No new linting errors introduced

### 3.3 Build Verification

```bash
npm run build
```

or equivalent build command for the project.

- [ ] Build completes successfully
- [ ] No errors or critical warnings

### 3.4 Pre-commit Checks

- [ ] Pre-commit hooks pass (if configured)
- [ ] No debugging code left (console.log, debugger, etc.)

### 3.5 Visual Verification

When a change affects user-facing UI, use the Playwright MCP server to:

- [ ] Start the dev server (or relevant preview).
- [ ] Navigate to the affected route.
- [ ] Capture screenshots at the relevant viewports (e.g., 375px, 768px, 1440px).
- [ ] For modified surfaces, also check out main, capture the "before" at the same viewports, then return to the feature branch.
- [ ] Attach screenshots to the PR description with clear before/after labels.

Save screenshots under .agent/screenshots/ticket-<number>/ so they're traceable. Do not commit them — upload to the PR directly via gh pr comment --body-file referencing the image, or use gh to attach via a GitHub-hosted upload.

**CHECKPOINT: All validation items complete?**

**If NO, fix issues before proceeding.**

---

## ⚪ PHASE 4: SUBMISSION

### 4.1 Push and Create PR

```bash
git push -u origin <branch-name>
```

Create PR with:

- **Title**: Conventional commit format (feat:, fix:, etc.)
- **Body**: Include ticket number, summary, test plan
- **Link**: Reference ticket (#<number>)
- **Screenshots (visual changes)**: If the change affects any user-facing UI, include screenshots in the PR description. Include before and after when modifying an existing surface. For new UI where no "before" exists, include after screenshots only and note it's a new surface. Capture the same viewport and state in both images so the diff is obvious.

```bash
gh pr create --title "feat: <description>" --body "..."
```

### 4.2 PR Review (MANDATORY)

Use the pr-reviewer agent to review:

```
Review PR #<number> comprehensively and post findings as PR review comment
```

- [ ] PR review completed by agent
- [ ] Review posted as PR comment using `gh pr review`

### 4.3 Address Feedback

**For EVERY piece of feedback:**

- Either fix the issue and update PR
- Or explain why it shouldn't be addressed
- For any issues that are judged to be valuable but out of scope, create a new ticket via the project's ticket provider using the MCP tool.

Post response using:

```bash
gh pr comment <number> --body "Addressed: ... / Not addressed: ..."
```

- [ ] All feedback addressed or justified, or a ticket has been created for the out of scope feedback.
- [ ] Response posted to PR

### 4.4 Remove label

Remove the "agent active" label from the ticket.

### 4.5 Final Steps

Add ammonl as a reviewer.

```bash
# Add reviewer
gh pr edit <number> --add-reviewer ammonl
```

Leave a comment on the ticket, referencing the PR and provide a summary of the implementation.

- [ ] Reviewer added (ammonl)
- [ ] Issue commented with PR link + implementation summary
- [ ] Move the ticket to "in review" status.
- [ ] Ready for final review

---

## Language & Spelling

Always use **American English** spelling and terminology in all written output — code comments, docstrings, log messages, commit messages, PR descriptions, documentation, and user-facing strings.

- Use `-ize` / `-ization`, not `-ise` / `-isation` (e.g., `initialize`, `organization`).
- Use `-or`, not `-our` (e.g., `color`, `behavior`, `favor`).
- Use `-er`, not `-re` (e.g., `center`, `meter`).
- Use single `l` in past tense where American English does (e.g., `canceled`, `traveled`, `modeled`).
- Prefer American vocabulary (e.g., `gray` not `grey`, `catalog` not `catalogue`).

This applies even when editing files that already contain British spellings — normalize to American English unless the surrounding identifier is a fixed external API name (e.g., a third-party library's `Colour` class) that cannot be changed.

## Command Style

Never chain commands with `&&`. Use separate commands instead.

Bad:

```bash
cd foo && npm install && npm test
```

Good:

```bash
cd foo
npm install
npm test
```

**Never use heredocs in Bash commands.** Heredocs embed newlines into the command string, which breaks permission pattern matching.

For multi-line `gh` command bodies, write to a temp file instead:

```bash
printf '%s' "body content here" > /tmp/pr-body.txt
gh pr create --title "..." --body-file /tmp/pr-body.txt
```

Or use a single-quoted string with explicit \n escaping if the body is short enough to fit on one line.

The key flags that accept files:

```
- `gh pr create --body-file <file>`
- `gh pr comment --body-file <file>`
- `gh pr review --body-file <file>`
- `gh issue comment --body-file <file>`
```

# Filing Tickets

If you need to create a ticket (e.g. to fix a bug you discovered or as a followup), use the MCP tool or local client. Do not add the label "claude" to the ticket. Put the ticket in TODO status and assign to Ammon Larson.

# Python Guidelines

Always use uv to manage python environments and run python commands. Check at the root folder for existing environments before creating a new one.
When working in the Python coding language, follow “The Hitchhiker’s Guide to Python” conventions for project structure, packaging, tooling, and general best practices:
Core principles

- Prefer readability and explicitness over cleverness.
- Keep modules small and cohesive; avoid deep inheritance and over-abstraction.
- Prefer the standard library where practical; add dependencies only when justified.
  Project layout and structure
- Default to a `src/` layout for packages (e.g., `src/<package_name>/...`) and keep import paths clean.
- Keep configuration, documentation, and tooling files at the repo root.
- Put tests in `tests/` and write tests that are fast, deterministic, and isolated.
- Organize code by feature/domain rather than by “layers” unless the project clearly benefits.
  Environment and dependencies
- Always assume an isolated virtual environment.
- Prefer pinned, reproducible dependencies (lockfile or pinned requirements).
- Do not instruct to modify global Python installations.
  Code style
- Follow PEP 8 naming and formatting conventions.
- Prefer f-strings, pathlib, context managers, and type hints where they improve clarity.
- Write docstrings for public modules/classes/functions; keep them concise and useful.
- Use exceptions intentionally; never blanket-catch without re-raising or logging.
  Tooling (assume these unless the user specifies otherwise)
- Formatting/linting: use Ruff (and Black only if requested or already present).
- Type checking: use mypy or pyright if the project uses typing seriously.
- Testing: use pytest; use fixtures; avoid network in unit tests.
- Logging: use the standard `logging` module; no print statements in library code.
  Async and concurrency
- Use asyncio only for I/O concurrency; avoid making everything async.
- Do not block the event loop; if forced to call blocking code from async code, use `asyncio.to_thread()`.
- Do not add numbering to comments.
- Do not mention specific tickets, issues, or bug numbers in comments.
- If a change is a reaction to a bug in existing code and would not have been commented if the code had been written that way initially, do not add that comment.

---

# 🎯 QUICK REFERENCE

## Every Task Checklist

```
Phase 1: Pre-Work
├─ view ticketissue, add labels, update status
├─ Create .agent/ticket-X-plan.md
└─ git checkout -b {branch_format}

Phase 2: Execution
├─ Write minimal code
├─ Follow project patterns
└─ Add validation + error handling

Phase 3: Validation
├─ npm test (if configured)
├─ npm run lint
├─ npm run build
└─ Pre-commit checks

Phase 4: Submission
├─ git push + create PR
├─ Agent review + post findings
├─ Address all feedback
└─ Remove "agent active"
├─ Add reviewer (ammonl)
├─ Comment on ticket
|_ Update ticket status
```

## Critical Reminders

**DON'T:**

- ❌ Forget ticket labels
- ❌ Skip planning document
- ❌ Modify unrelated code
- ❌ Skip PR review
- ❌ Ignore review feedback
- ❌ Force push to main

**DO:**

- ✅ Follow the phase workflow
- ✅ Validate required fields
- ✅ Provide user-facing errors
- ✅ Test before pushing
- ✅ Address all PR feedback
- ✅ Keep changes minimal

---

# ⚠️ WHY THIS MATTERS

**Skipping workflow phases leads to:**

- Missing labels → Lost tracking
- No planning → Wasted rework
- No validation → Broken builds
- No review → Critical bugs shipped

**Following this file ensures:**

- ✅ Consistent, high-quality code
- ✅ Proper tracking and documentation
- ✅ Caught bugs before merge
- ✅ Efficient workflow
- ✅ User trust maintained

---

**Remember: This file is not a suggestion. It is a requirement.**

**When in doubt, re-read this file. When finishing a task, verify all phases complete.**

# PROJECT-SPECIFIC INFORMATION

---

## IMPORTANT! Keep the '# PROJECT-SPECIFIC INFORMATION' header here -- everything above is automatically copied from the Claude configuration repo, and updated whenever the global instructions change. Everything below is project-specific, and should be edited as needed.

## Project Settings

- **Ticket Provider**: GitHub Issues
- **Branch Format**: `<type>/<ticket-number>` (e.g., `feature/123`)
- **Main Branch**: `main`

## What this repo is

A single Terraform root module that provisions one shared Postgres RDS instance and carves out an isolated database + login role + Secrets Manager secret per project. There is no application code — only `.tf` files and the GitHub Actions workflow that applies them.

The unit of change is almost always a one-line edit to `local.projects` in `projects.tf`. Anything bigger usually means rethinking the architecture, not adding code.

## Common commands

```bash
terraform fmt -check -recursive   # CI runs this; matches the lint gate
terraform init                    # required after backend or provider changes
terraform validate
terraform plan -var='allowed_ingress_cidrs=["<ip>/32"]'
terraform apply -var='allowed_ingress_cidrs=["<ip>/32"]'
```

`allowed_ingress_cidrs` defaults to `[]` (no ingress), so you must pass it on every local plan/apply that touches Postgres-level resources, or persist it in a gitignored `terraform.tfvars`. Without it, the `postgresql` provider can't reach RDS and Postgres-level applies fail.

There are no tests, no build step, and no `npm` / language tooling in this repo. CI is a lint gate only: `fmt -check` + `init` + `validate`. `terraform plan` and `apply` are operator-side — see the README's "Why GitHub Actions doesn't run `terraform apply`" section for why.

## Architecture — what requires reading multiple files

### Two providers, one apply

`providers.tf` configures both the `aws` provider and `cyrilgdn/postgresql`. The Postgres provider's connection string is derived from the RDS instance attributes that don't exist until AWS-level resources are applied. Terraform handles this implicitly via the dependency graph, but it has two consequences:

1. **First apply is fragile.** The provider tries to dial RDS during plan. On a brand-new state, `terraform plan` may fail until the RDS instance exists. The README's troubleshooting section documents the `role already exists` race; re-running apply is the standard fix.
2. **Network reachability is required wherever you run `terraform plan/apply`.** All `plan` and `apply` runs are operator-side (CI is lint-only) and the operator's IP must be in `allowed_ingress_cidrs`. If you split this into private RDS, the Postgres-level applies must move to inside the VPC — see the "Network access caveats" section in README.md.

### The per-project module is the only place projects exist

`modules/project/main.tf` defines what "a project" means: one `random_password`, one `postgresql_role`, one `postgresql_database`, and one `aws_secretsmanager_secret` + version. `projects.tf` instantiates this module via `for_each` over `local.projects`. To add or remove a project you edit only the list in `projects.tf` — never the module.

A project's identity is its name string. Renaming is a destroy-and-recreate (see ADDING_A_PROJECT.md FAQ). Project names are lowercase `snake_case`, no leading digits, and become the database name, the role `<name>_app`, and the secret `rds/shared/<name>`.

### State backend is bootstrapped out-of-band

`backend.tf` references an S3 bucket (`ammonl-db-tf-state`) and DynamoDB lock table (`ammonl-db-tf-locks`) in `eu-north-1`. These exist outside of Terraform's control because of the chicken-and-egg with the state backend — see README.md "One-time bootstrap" for how they were created. Don't try to manage them via this repo.

### CI/CD: lint only

`.github/workflows/terraform.yml` runs `fmt -check`, `init`, and `validate` on every PR and push to `main`. It does NOT run `terraform plan` or `apply` — those are operator-side because the GHA runner's IP isn't in `allowed_ingress_cidrs`. AWS auth is GitHub OIDC against the IAM role `gha-terraform-shared-db`; the role exists so `init` can read the S3 backend. When reviewing a PR, run `terraform plan` locally to get the authoritative diff, and verify it matches what ADDING_A_PROJECT.md describes (only additions for new projects, only destroys for removals).

## Conventions

- AWS region is `eu-north-1` everywhere (variable default + GHA env). Don't hardcode it elsewhere.
- The master credential lives at `rds/shared/master`; per-project secrets at `rds/shared/<name>`. Project apps must only have IAM access to their own secret ARN, never the master.
- Pre-existing resources (`deletion_protection = true`, `skip_final_snapshot = false`, `final_snapshot_identifier`) on `aws_db_instance.shared` are intentional safety guards. Don't remove them when refactoring.
- `*.tfvars` is gitignored on purpose because `allowed_ingress_cidrs` may contain operator IPs. Don't commit one.
