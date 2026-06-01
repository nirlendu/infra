#!/bin/bash
# Account-wide weekly cost audit (shared-infra / personal/infra).
#
# Surfaces the orphans Budgets + Anomaly Detector miss because each item is
# individually cheap but accumulates: unattached EBS, idle EIPs, stray NAT
# Gateways / load balancers, old snapshots, fat log groups, unexpected RDS.
# This is layer D16 of COST-GUARDRAILS.md. Acting on its findings is NOT optional.
#
# Runs anywhere with AWS creds — an EC2 host (cron, Monday 04:00 UTC, installed
# by a host's user-data) OR an operator workstation. No app-specific assumptions.
#
# Usage:
#   ./cost-audit.sh                       # log to stdout + $LOG
#   ./cost-audit.sh s3://bucket/prefix    # also ship the audit to S3 for history
#
# Env:
#   EXPECTED_EC2   expected running-instance count (default: unset → just reports)
#   EXPECTED_RDS   expected RDS count (default: 1, the shared Postgres)
#   AUDIT_REGION   override region (default: instance metadata, else us-east-1)

set -uo pipefail

REGION="${AUDIT_REGION:-$(curl -fsS --max-time 2 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")}"
TS=$(date -u +%Y%m%dT%H%M%SZ)
LOG="${COST_AUDIT_LOG:-/tmp/shared-cost-audit.log}"
EXPECTED_RDS="${EXPECTED_RDS:-1}"

# Optional argv $1 = s3://<bucket>/<prefix>. If omitted, audit only logs.
DEST="${1:-}"
BUCKET=""; PREFIX=""
if [ -n "${DEST}" ]; then
  BUCKET=$(echo "${DEST}" | sed -E 's|^s3://([^/]+)/?.*|\1|')
  PREFIX=$(echo "${DEST}" | sed -E 's|^s3://[^/]+/?(.*)|\1|')
fi

note() { echo "[$(date -u +%FT%TZ)] $*"; }

{
  echo "════════════════════════════════════════════════════════════════════"
  note "shared-infra cost-audit starting  (region: ${REGION})"
  echo ""

  # ── 1. Unattached EBS volumes ($0.08/GB-mo each — should be ZERO) ──────────
  note "1. Unattached EBS volumes (should be ZERO):"
  aws ec2 describe-volumes --region "${REGION}" --filters Name=status,Values=available \
    --query 'Volumes[*].[VolumeId,Size,CreateTime,Tags[?Key==`Name`].Value | [0]]' \
    --output table 2>&1 || echo "  (aws cli failed — IAM?)"
  echo ""

  # ── 2. Old EBS snapshots ───────────────────────────────────────────────────
  note "2. EBS snapshots older than 30 days:"
  CUTOFF=$(date -u -d '30 days ago' +%Y-%m-%d 2>/dev/null || date -u -v-30d +%Y-%m-%d)
  aws ec2 describe-snapshots --region "${REGION}" --owner-ids self \
    --query "Snapshots[?StartTime<'${CUTOFF}'].[SnapshotId,VolumeSize,StartTime,Description]" \
    --output table 2>&1 || echo "  (aws cli failed)"
  echo ""

  # ── 3. Running EC2 instances ───────────────────────────────────────────────
  note "3. Running EC2 instances${EXPECTED_EC2:+ (expected: ${EXPECTED_EC2})}:"
  aws ec2 describe-instances --region "${REGION}" \
    --filters Name=instance-state-name,Values=running,pending \
    --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,Tags[?Key==`Name`].Value | [0],LaunchTime]' \
    --output table 2>&1 || echo "  (aws cli failed)"
  echo ""

  # ── 4. Elastic IPs (unattached = $3.60/mo each) ────────────────────────────
  note "4. Elastic IP addresses (unattached costs \$3.60/mo each):"
  aws ec2 describe-addresses --region "${REGION}" \
    --query 'Addresses[*].[PublicIp,InstanceId,AssociationId,Tags[?Key==`Name`].Value | [0]]' \
    --output table 2>&1 || echo "  (aws cli failed)"
  echo ""

  # ── 5. NAT Gateways (≈ $33/mo idle each — expected ZERO) ───────────────────
  note "5. NAT Gateways (each ≈ \$33/mo idle — expected: ZERO):"
  NAT_COUNT=$(aws ec2 describe-nat-gateways --region "${REGION}" \
    --filter Name=state,Values=available --query 'length(NatGateways)' --output text 2>&1 || echo "?")
  echo "  count: ${NAT_COUNT}"
  if [ "${NAT_COUNT}" != "0" ] && [ "${NAT_COUNT}" != "None" ] && [ "${NAT_COUNT}" != "?" ]; then
    echo "  ⚠️  NAT GATEWAY DETECTED — investigate immediately."
    aws ec2 describe-nat-gateways --region "${REGION}" --filter Name=state,Values=available \
      --query 'NatGateways[*].[NatGatewayId,VpcId,State,CreateTime]' --output table
  fi
  echo ""

  # ── 6. Load balancers (expected ZERO) ──────────────────────────────────────
  note "6. Load balancers (expected: ZERO):"
  echo "  ALB/NLB count: $(aws elbv2 describe-load-balancers --region "${REGION}" --query 'length(LoadBalancers)' --output text 2>&1 || echo "?")"
  echo "  Classic ELB count: $(aws elb describe-load-balancers --region "${REGION}" --query 'length(LoadBalancerDescriptions)' --output text 2>&1 || echo "?")"
  echo ""

  # ── 7. RDS instances ───────────────────────────────────────────────────────
  note "7. RDS instances (expected: ${EXPECTED_RDS} shared):"
  aws rds describe-db-instances --region "${REGION}" \
    --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass,Engine,MultiAZ,AllocatedStorage,DBInstanceStatus]' \
    --output table 2>&1 || echo "  (aws cli failed)"
  echo ""

  # ── 8. CloudWatch log groups & retention ───────────────────────────────────
  note "8. CloudWatch log groups (ingest+storage cost; watch for null retention = forever):"
  aws logs describe-log-groups --region "${REGION}" \
    --query 'logGroups[*].[logGroupName,storedBytes,retentionInDays]' --output table 2>&1 || echo "  (aws cli failed)"
  echo ""

  # ── 9. S3 buckets + approximate size ────────────────────────────────────────
  note "9. S3 buckets (size via list — may be slow on big buckets):"
  aws s3 ls 2>&1 | while read -r line; do
    BNAME=$(echo "${line}" | awk '{print $NF}'); [ -z "${BNAME}" ] && continue
    SIZE=$(aws s3 ls "s3://${BNAME}" --recursive --summarize 2>/dev/null | tail -1 | awk '{print $3}')
    printf "  %-50s  %s bytes\n" "${BNAME}" "${SIZE:-unknown}"
  done
  echo ""

  # ── 10. Month-to-date spend (best-effort) ──────────────────────────────────
  note "10. Current month-to-date spend:"
  MTD=$(aws ce get-cost-and-usage --region us-east-1 \
    --time-period "Start=$(date -u +%Y-%m-01),End=$(date -u +%Y-%m-%d)" \
    --granularity MONTHLY --metrics UnblendedCost \
    --query 'ResultsByTime[0].Total.UnblendedCost.Amount' --output text 2>&1 || echo "n/a")
  echo "  MTD: \$${MTD}"
  echo ""
  note "shared-infra cost-audit complete"
  echo "════════════════════════════════════════════════════════════════════"
} | tee -a "${LOG}"

# Ship to S3 for off-host history.
if [ -n "${BUCKET}" ]; then
  AUDIT_FILE="/tmp/shared-cost-audit-${TS}.log"
  tail -n 500 "${LOG}" > "${AUDIT_FILE}" 2>/dev/null
  KEY="${PREFIX:+${PREFIX}/}${TS}.log"
  aws s3 cp "${AUDIT_FILE}" "s3://${BUCKET}/${KEY}" --storage-class STANDARD_IA --no-progress 2>/dev/null || true
  rm -f "${AUDIT_FILE}"
fi
