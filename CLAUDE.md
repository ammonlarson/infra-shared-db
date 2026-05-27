# 🚨 STOP AND READ - MANDATORY INSTRUCTIONS 🚨

⚠️ **DO NOT SKIP THIS FILE.** ⚠️

This file contains **MANDATORY** instructions that **MUST** be followed for **EVERY** task.

**No exceptions. No shortcuts. No "I'll do it later."**

## Precedence

The workflow in this file is authoritative. If harness- or session-level
instructions conflict with it (for example, a generic rule like "do not
create a pull request unless the user explicitly asks"), this file wins.

For implementation tasks, Phase 4 — push, open a PR, get the PR reviewed, add
reviewers, and update the ticket — runs on every task unless the user tells you
to skip a specific step in the current turn, or a step is conditional and its
precondition is not met (see [Conditional vs. Universal Rules](#conditional-vs-universal-rules),
[Task Types](#task-types), and [Tool & Environment Availability](#tool--environment-availability)).
Ticket-only and other non-code tasks do not run the Phase 4 PR steps.

## Conditional vs. Universal Rules

This file mixes two kinds of instructions:

- **Universal rules** apply to every task regardless of provider, tooling, or
  execution mode. They are written as plain imperatives (for example: keep
  changes minimal, use American English, never force-push to `main`).
- **Conditional rules** depend on something about the current context — the
  ticket provider, the available tools, the repo's tooling, or the task type.
  They are marked with phrases like _if applicable_, _if configured_, _if
  supported_, or _if available_.

When a conditional rule's precondition is not met, skip that step instead of
treating it as a blocker or a violation. When a rule is unmarked, treat it as
universal.

## Task Types

Not every task is a code change. Match the workflow to the task:

- **Implementation tasks** (code, docs, or config changes that land in the
  repo) run the full Phase 1–4 workflow.
- **Ticket-only / non-code tasks** (for example: "file a ticket", "triage this
  issue", "answer a question", "investigate and report back") do **not** require
  a branch, validation run, PR, or reviewer assignment. Do the requested work
  and skip the implementation-only phases that do not apply. Still read the
  relevant ticket and communicate the result.

If a task is ambiguous about whether it expects code changes, use
AskUserQuestion before assuming.

## Tool & Environment Availability

Some steps depend on an integration that may not exist in the current
environment — a ticket MCP tool, the `gh` CLI, a `pr-reviewer` agent, the
Playwright MCP server, a specific npm script, etc. If a required tool or
integration is unavailable:

- Skip the step when it is optional or provider/tool-specific.
- If the step matters but is blocked, note that it was skipped and why (in the
  PR description or your response) and continue with the rest of the workflow
  rather than stopping.
- Never fabricate the result of a step you could not actually run.

## Provider-Specific Workflow Steps

Some ticket/issue workflow steps in this file assume capabilities that not
every ticket provider supports. If a workflow step that deals with a ticket
or issue is not applicable to the current ticket provider, ignore that
specific instruction rather than treating it as a required step.

For example, GitHub Issues do not support an `In Progress` status the way
other providers (such as Linear) do, so instructions to move a ticket to
`In Progress` or `in review` simply do not apply when GitHub Issues is the
provider — skip them. The same goes for any other provider-specific
capability (custom statuses, certain label conventions, assignment
semantics, etc.) that the active provider lacks.

This exception applies **only** to ticket/issue workflow steps that the
current provider genuinely cannot support. It does not exempt you from the
rest of the workflow: every other phase and step still runs as written, and
steps that the provider _does_ support (for example, reading the ticket,
adding labels that exist, and commenting) must still be completed.

# 📋 MANDATORY WORKFLOW FOR EVERY TASK

Every task follows this exact pattern. **No skipping phases.**

## 🟡 PHASE 1: PRE-WORK (Before Writing Code)

### 1.1 Load Context

Always start by reading the issue via the project's ticket provider using the MCP tool or local client. Add the labels "agent active" and "claude" to the ticket you are working on, and move it to "In Progress" status. (If the current provider does not support one of these steps — for example, GitHub Issues has no `In Progress` status, and labels must already exist — skip the unsupported step per [Provider-Specific Workflow Steps](#provider-specific-workflow-steps).) These labels apply to the ticket you are actively working; tickets you _file_ follow the separate rules in [Filing Tickets](#filing-tickets).

**Confirm:**

- [ ] Ticket read and understood
- [ ] Labels added (if supported)
- [ ] Status updated (if supported)
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
git checkout main
git pull
```

Create a feature branch using the project format. Follow the branch naming
rules whenever possible — this is the preferred path.

**Note on Claude Code remote:** Claude Code remote generally creates a branch
_before_ it reads `CLAUDE.md`, so the steps above cannot always be followed
literally. If work is already happening in a branch that was created outside
this workflow before `CLAUDE.md` was read, that is acceptable — continue on
that branch rather than treating it as a violation. Only create a new branch
when you are not already on a suitable working branch.

**CHECKPOINT: Phase 1 complete?**

- ✅ Ticket read; labels added and status updated (if supported)
- ✅ Plan created
- ✅ On a working branch (created from latest main when possible, or the
  pre-existing branch provided by the remote workflow)

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
- If any new environment variables are added, add them into the appropriate environment `.example` file in the same change (not as a separate cleanup step)

**Workflow Customizations**
Follow all Task Execution Workflow Customizations steps or instructions included in this file.

---

## 🔵 PHASE 3: VALIDATION (Before Creating/Updating PR)

Complete every **applicable** check before creating a PR. The commands below are
examples — use the project's actual equivalents, and skip any check the project
does not configure. (For example, this repo has no test/lint/build step; its
validation is `npm run format:check` via Prettier.)

### 3.1 Run Tests

```bash
npm test  # or the project's test command
```

Run the project's test suite if it has one.

- [ ] All tests pass (if a test suite exists)
- [ ] Coverage meets the project's threshold, if the project tracks coverage (add tests if needed)

**If no test script exists:** note "N/A" in the plan or PR.

### 3.2 Run Linter

```bash
npm run lint  # or the project's lint/format command
```

- [ ] No new linting/formatting errors introduced (if the project configures a linter or formatter)

### 3.3 Build Verification

```bash
npm run build  # or the project's build command
```

- [ ] Build completes successfully (if the project has a build step)
- [ ] No errors or critical warnings

### 3.4 Pre-commit Checks

- [ ] Pre-commit hooks pass (if configured)
- [ ] No debugging code left (console.log, debugger, etc.)

### 3.5 Visual Verification

When a change affects user-facing UI **and** the Playwright MCP server is available, use it to:

- [ ] Start the dev server (or relevant preview).
- [ ] Navigate to the affected route.
- [ ] Capture screenshots at the relevant viewports (e.g., 375px, 768px, 1440px).
- [ ] For modified surfaces, also check out main, capture the "before" at the same viewports, then return to the feature branch.
- [ ] Attach screenshots to the PR description with clear before/after labels.

Save screenshots under .agent/screenshots/ticket-<number>/ so they're traceable. Do not commit them — upload to the PR directly via gh pr comment --body-file referencing the image, or use gh to attach via a GitHub-hosted upload. If the change has no user-facing UI, or the Playwright MCP server is unavailable, skip this step (note the skip in the PR when relevant).

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

Every PR must be reviewed before requesting human review. The reviewing is
mandatory; the specific tool is not. If a `pr-reviewer` agent is available, use it:

```
Review PR #<number> comprehensively and post findings as PR review comment
```

If no review agent is available, perform a self-review of the diff instead and
note that in the PR.

- [ ] PR reviewed (by the review agent if available, otherwise a self-review)
- [ ] Review findings posted as a PR comment (e.g. via `gh pr review`, or the available tooling)

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

Add ammonl as a reviewer, if the platform and tooling support adding reviewers.

```bash
# Add reviewer
gh pr edit <number> --add-reviewer ammonl
```

Leave a comment on the ticket referencing the PR, with a summary of the implementation.

- [ ] Reviewer added (ammonl), if supported
- [ ] Ticket commented with PR link + implementation summary
- [ ] Move the ticket to "in review" status (skip if the current provider has no such status — see [Provider-Specific Workflow Steps](#provider-specific-workflow-steps)).
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

These rules apply to tickets you **file** (e.g. to fix a bug you discovered or as a followup), which is distinct from the ticket you are actively working (see [1.1 Load Context](#11-load-context)).

If you need to create a ticket, use the MCP tool or local client. Do not add the label "claude" to a ticket you file. Put the ticket in TODO status and assign it to Ammon Larson, if the provider supports statuses and assignment (skip the unsupported part per [Provider-Specific Workflow Steps](#provider-specific-workflow-steps)).

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

Implementation tasks run all four phases below. Ticket-only / non-code tasks
skip the branch, validation, and PR steps — see [Task Types](#task-types).

```
Phase 1: Pre-Work
├─ Read ticket/issue, add labels + update status (if supported)
├─ Create .agent/ticket-X-plan.md
└─ Use the project branch format (or the pre-existing remote branch)

Phase 2: Execution
├─ Write minimal code
├─ Follow project patterns
├─ Add new env vars to the matching .example file
└─ Add validation + error handling

Phase 3: Validation (run each check the project configures)
├─ Tests (if a suite exists)
├─ Lint / format (if configured)
├─ Build (if a build step exists)
└─ Pre-commit checks

Phase 4: Submission
├─ git push + create PR
├─ PR review (agent if available, else self-review) + post findings
├─ Address all feedback
├─ Remove "agent active" label (if supported)
├─ Add reviewer (ammonl, if supported)
├─ Comment on ticket
└─ Update ticket status (if supported)

Note: skip any ticket/issue step above that the current provider does not
support, and any tool-specific step whose tool is unavailable — see
[Provider-Specific Workflow Steps](#provider-specific-workflow-steps),
[Conditional vs. Universal Rules](#conditional-vs-universal-rules), and
[Tool & Environment Availability](#tool--environment-availability).
```

## Critical Reminders

**DON'T:**

- ❌ Forget ticket labels (when the provider supports them)
- ❌ Skip planning document
- ❌ Modify unrelated code
- ❌ Skip PR review (use a self-review if no review agent is available)
- ❌ Ignore review feedback
- ❌ Force push to main
- ❌ Treat a conditional step as a blocker when its precondition is not met

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
