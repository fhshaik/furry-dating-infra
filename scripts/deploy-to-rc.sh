#!/usr/bin/env bash
# deploy-to-rc.sh  – same contract as deploy-to-ec2.sh but targets the RC host
set -euo pipefail

: "${AWS_REGION:?AWS_REGION is required}"
: "${AWS_ACCOUNT_ID:?AWS_ACCOUNT_ID is required}"
: "${ECR_REPO:?ECR_REPO is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${TARGET_HOST:?TARGET_HOST is required}"
: "${TARGET_SSH_USER:?TARGET_SSH_USER is required}"
: "${TARGET_SSH_KEY_PATH:?TARGET_SSH_KEY_PATH is required}"

IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}"
REMOTE_APP_DIR="${REMOTE_APP_DIR:-/opt/fur-connect}"
REMOTE_ENV_FILE="${REMOTE_ENV_FILE:-${REMOTE_APP_DIR}/rc.env}"
CONTAINER_NAME="${CONTAINER_NAME:-fur-connect-rc}"
CONTAINER_PORT_BIND="${CONTAINER_PORT_BIND:-127.0.0.1:8080:80}"

SSH_OPTS=(
  -i "${TARGET_SSH_KEY_PATH}"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ServerAliveInterval=15
  -o ConnectTimeout=10
)

if [ -n "${QA_APP_ENV:-}" ]; then
  ssh "${SSH_OPTS[@]}" "${TARGET_SSH_USER}@${TARGET_HOST}" \
    "sudo mkdir -p '${REMOTE_APP_DIR}' && sudo chown '${TARGET_SSH_USER}':'${TARGET_SSH_USER}' '${REMOTE_APP_DIR}'"
  printf '%s\n' "${QA_APP_ENV}" | ssh "${SSH_OPTS[@]}" "${TARGET_SSH_USER}@${TARGET_HOST}" \
    "cat > '${REMOTE_ENV_FILE}'"
fi

ssh "${SSH_OPTS[@]}" "${TARGET_SSH_USER}@${TARGET_HOST}" \
  "IMAGE_URI='${IMAGE_URI}' AWS_REGION='${AWS_REGION}' REMOTE_ENV_FILE='${REMOTE_ENV_FILE}' CONTAINER_NAME='${CONTAINER_NAME}' CONTAINER_PORT_BIND='${CONTAINER_PORT_BIND}' bash -s" <<'EOF'
set -euo pipefail

sudo systemctl enable --now docker

NGINX_CONF=/etc/nginx/conf.d/furry-dating.conf
if [ -f "${NGINX_CONF}" ] && ! grep -q 'location /ws/' "${NGINX_CONF}"; then
  sudo sed -i 's| location / {| location /ws/ {\n proxy_pass http://127.0.0.1:8080;\n proxy_http_version 1.1;\n proxy_set_header Upgrade $http_upgrade;\n proxy_set_header Connection "upgrade";\n proxy_set_header Host $host;\n proxy_read_timeout 86400;\n }\n\n location / {|' "${NGINX_CONF}"
  sudo nginx -t && sudo systemctl reload nginx
fi

aws ecr get-login-password --region "${AWS_REGION}" \
  | sudo docker login --username AWS --password-stdin \
    "$(printf '%s' "${IMAGE_URI}" | cut -d/ -f1)"

sudo docker pull "${IMAGE_URI}"
sudo docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
sudo docker run -d \
  --name "${CONTAINER_NAME}" \
  --add-host=host.docker.internal:host-gateway \
  --restart unless-stopped \
  --env-file "${REMOTE_ENV_FILE}" \
  -p "${CONTAINER_PORT_BIND}" \
  "${IMAGE_URI}"

for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8080/health >/dev/null && \
     curl -fsS http://127.0.0.1:8080/api/health >/dev/null; then
    echo "RC container healthy"
    exit 0
  fi
  sleep 10
done
sudo docker logs --tail 100 "${CONTAINER_NAME}" >&2
exit 1
EOF
