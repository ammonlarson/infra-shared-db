#!/usr/bin/env bash
#
# One-time setup: enable the repo-committed Git hooks for this clone.
# See README.md (Contribution Guidelines).

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

existing="$(git config --get core.hooksPath || true)"
if [[ -n "$existing" && "$existing" != ".githooks" ]]; then
  echo "⚠️  core.hooksPath is currently set to '$existing'."
  echo "    Overwriting with '.githooks'."
fi

git config core.hooksPath .githooks
echo "✅ Git hooks enabled (core.hooksPath = .githooks)"

if command -v tflint >/dev/null 2>&1; then
  echo "→ Initializing tflint plugins"
  tflint --init >/dev/null
  echo "✅ tflint plugins ready"
else
  echo "⚠️  tflint not found in PATH. Install before committing:"
  echo "    brew install tflint   # macOS"
  echo "    or see https://github.com/terraform-linters/tflint#installation"
fi
