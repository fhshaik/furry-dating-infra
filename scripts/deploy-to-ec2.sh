#!/usr/bin/env bash
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
REMOTE_ENV_FILE="${REMOTE_ENV_FILE:-${REMOTE_APP_DIR}/qa.env}"
CONTAINER_NAME="${CONTAINER_NAME:-fur-connect}"
CONTAINER_PORT_BIND="${CONTAINER_PORT_BIND:-127.0.0.1:8080:80}"
SSH_OPTS=(
  -i "${TARGET_SSH_KEY_PATH}"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ServerAliveInterval=15
  -o ConnectTimeout=10
)

if [ -n "${QA_APP_ENV:-}" ]; then
  ssh "${SSH_OPTS[@]}" "${TARGET_SSH_USER}@${TARGET_HOST}" "sudo mkdir -p '${REMOTE_APP_DIR}' && sudo chown '${TARGET_SSH_USER}':'${TARGET_SSH_USER}' '${REMOTE_APP_DIR}'"
  printf '%s\n' "${QA_APP_ENV}" | ssh "${SSH_OPTS[@]}" "${TARGET_SSH_USER}@${TARGET_HOST}" "cat > '${REMOTE_ENV_FILE}'"
fi

ssh "${SSH_OPTS[@]}" "${TARGET_SSH_USER}@${TARGET_HOST}" "IMAGE_URI='${IMAGE_URI}' AWS_REGION='${AWS_REGION}' REMOTE_ENV_FILE='${REMOTE_ENV_FILE}' CONTAINER_NAME='${CONTAINER_NAME}' CONTAINER_PORT_BIND='${CONTAINER_PORT_BIND}' bash -s" <<'EOF'
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required on the QA instance. Install it once before running this workflow." >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI is required on the QA instance for ECR login." >&2
  exit 1
fi

if [ ! -f "${REMOTE_ENV_FILE}" ]; then
  echo "Missing runtime env file at ${REMOTE_ENV_FILE}. Create it on the host or pass QA_APP_ENV from GitHub Secrets." >&2
  exit 1
fi

sudo systemctl enable --now docker
aws ecr get-login-password --region "${AWS_REGION}" | sudo docker login --username AWS --password-stdin "$(printf '%s' "${IMAGE_URI}" | cut -d/ -f1)"
sudo docker pull "${IMAGE_URI}"
echo "--- Ensuring MySQL database exists ---"
sudo docker run --rm --env-file "${REMOTE_ENV_FILE}" --entrypoint python3 "${IMAGE_URI}" -c "import pymysql,os,sys; h=os.environ.get('MYSQL_HOST'); u=os.environ.get('MYSQL_USER'); p=os.environ.get('MYSQL_PASSWORD'); port=int(os.environ.get('MYSQL_PORT',3306)); db=os.environ.get('MYSQL_DATABASE','furconnect'); conn=pymysql.connect(host=h,user=u,password=p,port=port,connect_timeout=10); conn.cursor().execute('CREATE DATABASE IF NOT EXISTS ' + db + ' CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci'); conn.commit(); conn.close(); print('DB ' + db + ' ready')"
sudo docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
sudo docker run -d \
  --name "${CONTAINER_NAME}" \
      --add-host=host.docker.internal:host-gateway \
  --restart unless-stopped \
  --env-file "${REMOTE_ENV_FILE}" \
  -p "${CONTAINER_PORT_BIND}" \
  "${IMAGE_URI}"

for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8080/health >/dev/null && curl -fsS http://127.0.0.1:8080/api/health >/dev/null; then
    exit 0
  fi
  sleep 10
done

sudo docker logs --tail 100 "${CONTAINER_NAME}" >&2
exit 1
EOF
