#!/bin/bash
# Terraform template: launch using templatefile(), not directly on your laptop.
set -Eeuo pipefail
exec > >(tee -a /var/log/nodejs-demoapp-bootstrap.log /dev/console) 2>&1
trap 'status=$?; echo "Bootstrap failed at line $LINENO (exit $status)"; docker logs --tail 100 nodejs-demoapp 2>/dev/null || true; exit "$status"' ERR

export AWS_DEFAULT_REGION='${aws_region}'
export AWS_PAGER=''
IMAGE='${docker_image}'
REGISTRY=$(printf '%s' "$IMAGE" | cut -d/ -f1)

retry() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if "$@"; then return 0; fi
    echo "Attempt $attempt failed: $1"
    sleep 10
  done
  return 1
}

# Avoid a full OS upgrade on the critical bootstrap path.
retry dnf install -y docker
if ! command -v aws >/dev/null 2>&1; then
  retry dnf install -y awscli2
fi
if ! command -v curl >/dev/null 2>&1; then
  retry dnf install -y curl-minimal
fi
systemctl enable --now docker
# Standard AL2023 AMIs include the SSM agent; the instance role grants access.
systemctl enable --now amazon-ssm-agent

ecr_login() {
  # Explicitly propagate both sides of the pipeline even inside retry().
  aws ecr get-login-password --region "$AWS_DEFAULT_REGION" |
    docker login --username AWS --password-stdin "$REGISTRY"
}
retry ecr_login
# t3 instances and the selected AMI are x86_64. Fail clearly on ARM-only images.
retry docker pull --platform linux/amd64 "$IMAGE"
docker logout "$REGISTRY"

if docker container inspect nodejs-demoapp >/dev/null 2>&1; then
  docker stop --time 35 nodejs-demoapp
  docker rm nodejs-demoapp
fi
docker run -d \
  --name nodejs-demoapp \
  --restart unless-stopped \
  --init \
  --stop-timeout 35 \
  --log-driver json-file --log-opt max-size=10m --log-opt max-file=3 \
  --publish '${app_port}:${container_port}' \
  --env 'PORT=${container_port}' \
  --env NODE_ENV=production \
  "$IMAGE"

for attempt in $(seq 1 60); do
  status=$(curl --silent --output /dev/null --write-out '%%{http_code}' \
    --connect-timeout 2 --max-time 3 'http://127.0.0.1:${app_port}${health_check_path}' || true)
  if [ "$status" = 200 ]; then
    echo "nodejs-demoapp is ready on EC2 port ${app_port}"
    exit 0
  fi
  sleep 2
done
echo "Application did not become ready within the startup deadline"
docker logs --tail 100 nodejs-demoapp || true
exit 1
