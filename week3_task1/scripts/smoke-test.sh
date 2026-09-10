#!/usr/bin/env bash
# Read-only deployment verification. Terraform apply does not await ASG refresh.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ENVIRONMENT=${1:-dev}
case "$ENVIRONMENT" in dev|production) ;; *) echo 'Use dev or production' >&2; exit 1;; esac
tf_output() { python3 "$ROOT/scripts/terraform.py" "$ENVIRONMENT" output -raw "$1"; }
REGION=$(tf_output aws_region)
URL=$(tf_output app_url)
TARGET_GROUP=$(tf_output target_group_arn)
ASG=$(tf_output asg_name)
export AWS_PAGER=''

for attempt in $(seq 1 90); do
  REFRESH=$(aws autoscaling describe-instance-refreshes --region "$REGION" \
    --auto-scaling-group-name "$ASG" --max-records 1 --query 'InstanceRefreshes[0].Status' --output text)
  case "$REFRESH" in
    Failed|Cancelled|RollbackFailed|RollbackSuccessful)
      echo "Latest instance refresh ended with $REFRESH. Inspect ASG activity history." >&2
      exit 1;;
  esac
  DESIRED=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" \
    --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0].DesiredCapacity' --output text)
  HEALTHY=$(aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$TARGET_GROUP" \
    --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" --output text)
  if { [ "$REFRESH" = Successful ] || [ "$REFRESH" = None ]; } && [ "$HEALTHY" -ge "$DESIRED" ] && [ "$HEALTHY" -gt 0 ]; then
    HOME_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$URL/" || true)
    HEALTH_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$URL/healthz" || true)
    if [ "$HOME_CODE" = 200 ] && [ "$HEALTH_CODE" = 200 ]; then
      echo "PASS: $HEALTHY healthy targets; HTTP 200 at $URL/ and $URL/healthz"
      exit 0
    fi
  fi
  echo "Waiting: refresh=$REFRESH healthy=$HEALTHY desired=$DESIRED ($attempt/90)"
  sleep 10
done
aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$TARGET_GROUP"
echo 'Deployment did not become healthy within 15 minutes.' >&2
exit 1
