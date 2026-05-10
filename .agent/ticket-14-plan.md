# Ticket 14 — Fix commit-msg diagnostic to list all 15 allowed types

## Analysis

### Current state

`.githooks/commit-msg` has two human-readable strings that are out of sync with
the validation regex (which itself is correct and accepts all 15 types):

1. **Line 31** — the "Missing or invalid type prefix" diagnostic enumerates
   only 13 of the 15 accepted types, omitting `infra` and `ux`:

   ```bash
   echo "   Must start with: feat, fix, docs, refactor, perf, test, build, ci, chore, revert, i18n, ui, or agent"
   ```

2. **Line 52** — the "Expected:" hint is missing the `<type>`, `<scope>`, and
   `<summary>` placeholders (likely stripped by an earlier shell-quoting
   round-trip):

   ```bash
   echo "Expected: [optional scope]: "
   ```

### Target state

1. Diagnostic enumerates all 15 allowed types, in the same order they appear
   in the regex:
   `feat, fix, docs, refactor, perf, test, build, ci, chore, revert, i18n, ui, agent, infra, ux`.
2. "Expected:" line shows the full template:
   `<type>[(<scope>)]: <summary>`.
3. No regex changes — purely human-readable strings.

### Approach

Two single-line `echo` edits in `.githooks/commit-msg`. No other files need
to change — README.md already documents all 15 types correctly under
"Commit message format".

## Task checklist

- [ ] Update line 31 to list all 15 types.
- [ ] Update line 52 to show the full `<type>[(<scope>)]: <summary>` template.
- [ ] Verify `terraform fmt -check -recursive` and `terraform validate` still pass
      (no `.tf` changes, but the gate must remain green).
- [ ] Smoke-test the hook locally with a malformed commit to confirm the
      diagnostic prints correctly.
- [ ] Commit, push, open PR linking #14.

## Implementation summary

- **Files modified**: `.githooks/commit-msg` (two `echo` strings).
- **Estimated impact**: contributor-visible diagnostic only; no behavior change
  in what the hook accepts or rejects.
- **Test plan**: run the hook against a malformed commit message and confirm
  the printed enumeration includes `infra` and `ux`, and the "Expected:" line
  shows `<type>[(<scope>)]: <summary>`.
