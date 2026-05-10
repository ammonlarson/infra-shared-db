# Ticket 17: Align README commit-message template with commit-msg hook

## Analysis

**Current state:**
- `README.md` line 102 shows the commit message format as:
  ```
  <type>(<optional-scope>): <summary>
  ```
- `.githooks/commit-msg` line 52 prints the expected format as:
  ```
  <type>[(<scope>)]: <summary>
  ```

Both forms convey the same meaning ("scope is optional"), but the bracket-around-the-paren notation `[(<scope>)]` is the more standard Conventional Commits convention. The hook is the more correct of the two; the README should be aligned to match.

**Target state:**
- `README.md` "Commit message format" template uses `<type>[(<scope>)]: <summary>`.
- The hook stays as-is.
- No code changes — docs-only.

**Approach:**
- Single one-line edit to `README.md` line 102.

## Task Checklist

- [x] Read ticket and add labels.
- [x] Create planning document.
- [x] Edit `README.md` line 102.
- [x] Run `terraform fmt -check -recursive` (no `.tf` changes; tool unavailable locally, CI runs the gate).
- [x] Commit on branch `claude/ticket-17-task-afDfK` with conventional message.
- [x] Push branch and open PR.
- [x] Run pr-reviewer agent.
- [x] Address feedback / add reviewer / comment ticket / remove `agent active`.

## Implementation Summary

- Files to modify: `README.md` (1 line).
- Estimated impact: docs-only; no terraform/runtime changes.
- Tests: N/A (no test suite in this repo). CI lint gate (`fmt -check`, `init`, `validate`) is unaffected by README changes but will run on PR.
