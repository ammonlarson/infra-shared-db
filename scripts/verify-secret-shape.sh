#!/usr/bin/env bash
#
# Verify that a shared-db Secrets Manager payload matches the contract in
# schemas/secret.schema.json.
#
# This is the non-manual replacement for the "aws ... | jq 'keys'" eyeball
# check in ADDING_A_PROJECT.md and SECRET_SCHEMA.md. It is safe to call from a
# consumer's deploy pipeline or CI: every required field is checked for presence
# and correct JSON type, and the script exits non-zero on any mismatch.
#
# Optional / implementation-detail fields are allowed: only the stable contract
# fields (the schema's "required" set) are enforced, so a payload that grows new
# keys later still passes.
#
# Usage:
#   scripts/verify-secret-shape.sh <secret-id> [aws-region]
#   scripts/verify-secret-shape.sh rds/shared/greenspace_staging eu-north-1
#
#   # Validate a payload from stdin without touching AWS:
#   cat payload.json | scripts/verify-secret-shape.sh --stdin
#
# Region resolution (when fetching from AWS): the [aws-region] argument, else
# $AWS_REGION, else eu-north-1.
#
# Requires: jq. Requires the AWS CLI only when fetching a secret (not for
# --stdin).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_FILE="${SECRET_SCHEMA_FILE:-$SCRIPT_DIR/../schemas/secret.schema.json}"

die() {
  echo "error: $*" >&2
  exit 2
}

usage() {
  sed -n '3,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

command -v jq >/dev/null 2>&1 || die "jq is required but not found in PATH"
[[ -f "$SCHEMA_FILE" ]] || die "schema not found: $SCHEMA_FILE"

case "${1:-}" in
  "" | -h | --help) usage 0 ;;
esac

# Obtain the payload, either from stdin or by fetching the secret from AWS.
if [[ "$1" == "--stdin" ]]; then
  payload="$(cat)"
  source_desc="stdin"
else
  secret_id="$1"
  region="${2:-${AWS_REGION:-eu-north-1}}"
  command -v aws >/dev/null 2>&1 || die "aws CLI is required to fetch a secret"
  payload="$(aws secretsmanager get-secret-value \
    --secret-id "$secret_id" \
    --region "$region" \
    --query SecretString --output text)" || die "failed to fetch secret '$secret_id' in '$region'"
  source_desc="$secret_id ($region)"
fi

printf '%s' "$payload" | jq -e . >/dev/null 2>&1 \
  || die "payload for $source_desc is not valid JSON"

# Validate the payload against the schema's required fields and their types.
# jq reports "number" for both integer and number, so map those before compare.
problems="$(
  printf '%s' "$payload" | jq -r --slurpfile schema "$SCHEMA_FILE" '
    ($schema[0]) as $s
    | . as $p
    | $s.required[]
    | . as $k
    | if ($p | has($k) | not)
      then "missing required field: \($k)"
      else
        ($s.properties[$k].type) as $want_raw
        | (if $want_raw == "integer" or $want_raw == "number"
           then "number" else $want_raw end) as $want
        | ($p[$k] | type) as $got
        | if $got != $want
          then "field \($k): expected \($want_raw), got \($got)"
          else empty end
      end
  '
)"

if [[ -n "$problems" ]]; then
  echo "✗ $source_desc does not match the shared-db secret contract:" >&2
  while IFS= read -r line; do
    [[ -n "$line" ]] && echo "    - $line" >&2
  done <<<"$problems"
  echo "  See SECRET_SCHEMA.md / schemas/secret.schema.json for the contract." >&2
  exit 1
fi

echo "✓ $source_desc matches the shared-db secret contract (all required fields present and well-typed)."
