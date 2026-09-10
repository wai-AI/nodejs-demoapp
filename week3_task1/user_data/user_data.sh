#!/bin/bash

set -euo pipefail

dnf install -y docker
systemctl enable --now docker

IMAGE='${docker_image}'
REGISTRY=$(echo "$IMAGE" | cut -d/ -f1)

aws ecr get-login-password --region '${aws_region}' |
  docker login --username AWS --password-stdin "$REGISTRY"

docker pull --platform linux/amd64 "$IMAGE"

docker run -d \
  --name nodejs-demoapp \
  --restart unless-stopped \
  --init \
  --publish '${app_port}:${container_port}' \
  --env 'PORT=${container_port}' \
  --env NODE_ENV=production \
  "$IMAGE"
