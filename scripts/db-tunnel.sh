#!/usr/bin/env bash
#
# Open an SSM port-forward from your laptop to the private shared RDS instance.
#
# RDS is publicly_accessible = false; the only inbound path is the SSM bastion.
# This script finds the bastion and the RDS endpoint, then starts an
# AWS-StartPortForwardingSessionToRemoteHost session that maps a local port to
# RDS:5432. Leave it running in one terminal and, in another, point
# `terraform plan`/`apply` (or psql) at localhost.
#
# The Terraform postgresql provider already defaults to 127.0.0.1:5432
# (var.postgres_host / var.postgres_port), so with the default local port no
# extra Terraform config is needed. If you forward to a different local port,
# pass the same value to Terraform via -var='postgres_port=...'.
#
# Usage:
#   scripts/db-tunnel.sh [local-port] [aws-region]
#   scripts/db-tunnel.sh              # localhost:5432 -> RDS, region default
#   scripts/db-tunnel.sh 15432        # localhost:15432 -> RDS
#
# Region resolution: the [aws-region] argument, else $AWS_REGION, else
# eu-north-1.
#
# Requires: aws CLI and the Session Manager plugin
# (https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).

set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 2
}

case "${1:-}" in
  -h | --help)
    sed -n '/^# Open an SSM/,/install-plugin\.html)\.$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

LOCAL_PORT="${1:-5432}"
REGION="${2:-${AWS_REGION:-eu-north-1}}"

command -v aws >/dev/null 2>&1 || die "aws CLI is required but not found in PATH"
aws ssm help >/dev/null 2>&1 || true
command -v session-manager-plugin >/dev/null 2>&1 \
  || die "the Session Manager plugin is required: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"

# Discover the bastion by its Name tag (set in bastion.tf). Only a running
# instance can host a session.
bastion_id="$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=tag:Name,Values=shared-db-bastion" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text 2>/dev/null)" || die "failed to query EC2 for the bastion"
[[ -n "$bastion_id" && "$bastion_id" != "None" ]] \
  || die "no running 'shared-db-bastion' instance found in $REGION"

# Discover the private RDS endpoint — the far side of the forward.
rds_host="$(aws rds describe-db-instances \
  --region "$REGION" \
  --db-instance-identifier shared-postgres \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text 2>/dev/null)" || die "failed to query RDS for the shared-postgres endpoint"
[[ -n "$rds_host" && "$rds_host" != "None" ]] \
  || die "could not resolve the shared-postgres endpoint in $REGION"

echo "Forwarding localhost:${LOCAL_PORT} -> ${rds_host}:5432 via bastion ${bastion_id} (${REGION})."
echo "Leave this running; in another terminal run terraform/psql against localhost:${LOCAL_PORT}."
[[ "$LOCAL_PORT" != "5432" ]] \
  && echo "Note: pass -var='postgres_port=${LOCAL_PORT}' to terraform since you changed the local port."

exec aws ssm start-session \
  --region "$REGION" \
  --target "$bastion_id" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${rds_host}\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}"
