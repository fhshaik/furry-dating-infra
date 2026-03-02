#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?AWS_REGION is required}"
: "${AWS_ACCOUNT_ID:?AWS_ACCOUNT_ID is required}"
: "${ECR_REPO:?ECR_REPO is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${SMOKE_HOST:?SMOKE_HOST is required}"
: "${SMOKE_SSH_KEY_PATH:?SMOKE_SSH_KEY_PATH is required}"
: "${SMOKE_SSH_USER:=ec2-user}"

IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}"
SSH_OPTS=(
  -i "${SMOKE_SSH_KEY_PATH}"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ServerAliveInterval=15
  -o ConnectTimeout=10
)

for _ in $(seq 1 30); do
  if ssh "${SSH_OPTS[@]}" "${SMOKE_SSH_USER}@${SMOKE_HOST}" "echo ready" >/dev/null 2>&1; then
    break
  fi
  sleep 10
done

scp "${SSH_OPTS[@]}" templates/smoke-test.env "${SMOKE_SSH_USER}@${SMOKE_HOST}:/tmp/fur-connect-smoke.env"

ssh "${SSH_OPTS[@]}" "${SMOKE_SSH_USER}@${SMOKE_HOST}" "IMAGE_URI='${IMAGE_URI}' AWS_REGION='${AWS_REGION}' bash -s" <<'EOF'
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  sudo dnf install -y docker
fi

sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user || true

aws ecr get-login-password --region "${AWS_REGION}" | sudo docker login --username AWS --password-stdin "$(printf '%s' "${IMAGE_URI}" | cut -d/ -f1)"
sudo docker pull "${IMAGE_URI}"
sudo docker rm -f fur-connect-smoke >/dev/null 2>&1 || true
sudo docker run -d \
  --name fur-connect-smoke \
  --restart unless-stopped \
  --env-file /tmp/fur-connect-smoke.env \
  -e RUN_DB_MIGRATIONS=false \
  -p 80:80 \
  "${IMAGE_URI}"

for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1/health >/dev/null && curl -fsS http://127.0.0.1/api/health >/dev/null; then
    break
  fi
  sleep 10
done

curl -fsS http://127.0.0.1/health
curl -fsS http://127.0.0.1/api/health
sudo docker logs --tail 50 fur-connect-smoke
EOF
