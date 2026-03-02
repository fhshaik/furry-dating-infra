# furry-dating-infra

Infrastructure automation for FurConnect nightly CI/CD to AWS EC2.

## What this repo does

- builds a single deployable Docker image from the separate `furry-dating-app` source repo
- pushes that image to `233683990680.dkr.ecr.us-east-1.amazonaws.com/fur_connect_ecr_repo`
- provisions a temporary EC2 instance for smoke testing
- deploys the validated image to the QA EC2 host over SSH
- includes a helper script for host-level nginx + Let's Encrypt TLS

## Required GitHub Secrets

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `AWS_ACCOUNT_ID`
- `ECR_REPO`
- `QA_HOST`
- `QA_SSH_USER`
- `QA_SSH_PRIVATE_KEY`
- optional `QA_APP_ENV`

`QA_APP_ENV` is a multiline env file payload for the container. If omitted, the workflow expects `/opt/fur-connect/qa.env` to already exist on the QA host.

## Required GitHub Variables

- `TEMP_INSTANCE_AMI_ID`
- `TEMP_INSTANCE_TYPE`
- `TEMP_INSTANCE_SUBNET_ID`
- `TEMP_INSTANCE_SECURITY_GROUP_ID`
- `TEMP_INSTANCE_PROFILE_NAME`

The temporary-instance security group should expose SSH only from a controlled source range and should allow outbound access to ECR.

## Workflows

- [nightly.yml](/Users/faadilshaik/Documents/GitHub/furry-dating-infra/.github/workflows/nightly.yml): nightly build, smoke test, and QA deploy
- [manual-deploy.yml](/Users/faadilshaik/Documents/GitHub/furry-dating-infra/.github/workflows/manual-deploy.yml): redeploy an existing ECR tag to QA

## QA host expectations

- EC2 instance `i-0a7aad52a9deef428`
- public IP `3.228.1.166`
- SSH user `ec2-user`
- IAM role `LabRole` with ECR pull permissions
- Docker installed
- AWS CLI installed
- host nginx and certbot configured to terminate TLS and proxy to `127.0.0.1:8080`

Use [setup-certbot-nginx.sh](/Users/faadilshaik/Documents/GitHub/furry-dating-infra/scripts/setup-certbot-nginx.sh) after the Route 53 record points at the QA host.
