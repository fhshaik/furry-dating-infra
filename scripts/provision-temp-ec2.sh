#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?AWS_REGION is required}"
: "${TEMP_INSTANCE_AMI_ID:?TEMP_INSTANCE_AMI_ID is required}"
: "${TEMP_INSTANCE_TYPE:=t3.small}"
: "${TEMP_INSTANCE_SUBNET_ID:?TEMP_INSTANCE_SUBNET_ID is required}"
: "${TEMP_INSTANCE_SECURITY_GROUP_ID:?TEMP_INSTANCE_SECURITY_GROUP_ID is required}"
: "${TEMP_INSTANCE_PROFILE_NAME:?TEMP_INSTANCE_PROFILE_NAME is required}"

INSTANCE_NAME="${TEMP_INSTANCE_NAME:-fur-connect-nightly-smoke}"
KEY_NAME="${TEMP_INSTANCE_KEY_NAME:-fur-connect-nightly-${GITHUB_RUN_ID:-manual}-$(date +%s)}"
KEY_PATH="${RUNNER_TEMP:-/tmp}/${KEY_NAME}.pem"
INSTANCE_ID=""

cleanup_on_error() {
  local exit_code="$1"
  if [ "${exit_code}" -eq 0 ]; then
    return
  fi
  if [ -n "${INSTANCE_ID}" ]; then
    aws ec2 terminate-instances --region "${AWS_REGION}" --instance-ids "${INSTANCE_ID}" >/dev/null 2>&1 || true
  fi
  aws ec2 delete-key-pair --region "${AWS_REGION}" --key-name "${KEY_NAME}" >/dev/null 2>&1 || true
  rm -f "${KEY_PATH}"
}

trap 'cleanup_on_error $?' EXIT

aws ec2 create-key-pair \
  --region "${AWS_REGION}" \
  --key-name "${KEY_NAME}" \
  --query "KeyMaterial" \
  --output text > "${KEY_PATH}"
chmod 600 "${KEY_PATH}"

RUN_ARGS=(
  --region "${AWS_REGION}"
  --image-id "${TEMP_INSTANCE_AMI_ID}"
  --instance-type "${TEMP_INSTANCE_TYPE}"
  --subnet-id "${TEMP_INSTANCE_SUBNET_ID}"
  --security-group-ids "${TEMP_INSTANCE_SECURITY_GROUP_ID}"
  --iam-instance-profile "Name=${TEMP_INSTANCE_PROFILE_NAME}"
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}},{Key=Project,Value=furry-dating},{Key=Lifecycle,Value=ephemeral}]"
  --count 1
  --query "Instances[0].InstanceId"
  --output text
  --key-name "${KEY_NAME}"
)

INSTANCE_ID="$(aws ec2 run-instances "${RUN_ARGS[@]}")"
aws ec2 wait instance-running --region "${AWS_REGION}" --instance-ids "${INSTANCE_ID}"
aws ec2 wait instance-status-ok --region "${AWS_REGION}" --instance-ids "${INSTANCE_ID}"

PUBLIC_IP="$(
  aws ec2 describe-instances \
    --region "${AWS_REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text
)"

if [ -z "${PUBLIC_IP}" ] || [ "${PUBLIC_IP}" = "None" ]; then
  echo "Temporary instance does not have a public IP address." >&2
  exit 1
fi

printf 'instance_id=%s\n' "${INSTANCE_ID}" >> "${GITHUB_OUTPUT:-/dev/stdout}"
printf 'public_ip=%s\n' "${PUBLIC_IP}" >> "${GITHUB_OUTPUT:-/dev/stdout}"
printf 'key_name=%s\n' "${KEY_NAME}" >> "${GITHUB_OUTPUT:-/dev/stdout}"
printf 'key_path=%s\n' "${KEY_PATH}" >> "${GITHUB_OUTPUT:-/dev/stdout}"
