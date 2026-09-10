#!/usr/bin/env bash
# Build and smoke-test the adjacent fork before publishing it to private ECR.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ENVIRONMENT=${1:-dev}
APP_DIR=${2:-"$ROOT/../nodejs-demoapp"}
REGION=${AWS_REGION:-eu-central-1}
REPOSITORY=${ECR_REPOSITORY:-nodejs-demoapp}
case "$ENVIRONMENT" in dev|production) ;; *) echo 'Use dev or production' >&2; exit 1;; esac

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
TAG="$ENVIRONMENT-$(date -u +%Y%m%dT%H%M%SZ)"
IMAGE="$REGISTRY/$REPOSITORY:$TAG"
aws ecr describe-repositories --region "$REGION" --repository-names "$REPOSITORY" >/dev/null
docker info >/dev/null
docker buildx build --platform linux/amd64 --load -f "$APP_DIR/build/Dockerfile" -t "$IMAGE" "$APP_DIR"

CONTAINER=$(docker run --platform linux/amd64 -d --init --env PORT=3000 "$IMAGE")
cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT
READY=false
for attempt in $(seq 1 60); do
  if docker exec "$CONTAINER" node -e '
    Promise.all(["/", "/healthz"].map(async path => {
      const r = await fetch("http://127.0.0.1:3000" + path);
      if (r.status !== 200) throw Error(path + ": " + r.status);
    })).catch(e => { console.error(e); process.exit(1) });
  '; then READY=true; break; fi
  sleep 2
done
if [ "$READY" != true ]; then docker logs "$CONTAINER"; exit 1; fi
cleanup
trap - EXIT

aws ecr get-login-password --region "$REGION" |
  docker login --username AWS --password-stdin "$REGISTRY"
docker push "$IMAGE"
DIGEST=$(aws ecr describe-images --region "$REGION" --repository-name "$REPOSITORY" \
  --image-ids "imageTag=$TAG" --query 'imageDetails[0].imageDigest' --output text)
case "$DIGEST" in sha256:*) ;; *) echo 'ECR did not return an image digest' >&2; exit 1;; esac
FILE="$ROOT/infrastructure/env/$ENVIRONMENT.image.local.tfvars"
printf 'docker_image = "%s/%s@%s"\n' "$REGISTRY" "$REPOSITORY" "$DIGEST" > "$FILE"
echo "Published $IMAGE"
echo "Deploy the digest using -var-file=../env/$ENVIRONMENT.image.local.tfvars"
