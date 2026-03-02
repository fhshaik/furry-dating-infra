# FurConnect Infra Architecture

## Deployment model

- source code lives in the separate `furry-dating-app` repository
- this infra repo builds one bundled Docker image containing:
  - the compiled SPA
  - the Python backend
  - nginx proxying `/api` and `/ws` to the backend inside the same container
- MySQL stays external on RDS

## Nightly flow

1. [nightly.yml](/Users/faadilshaik/Documents/GitHub/furry-dating-infra/.github/workflows/nightly.yml) checks out this repo and the app repo.
2. GitHub Actions authenticates to AWS with static access keys from GitHub Secrets.
3. The workflow builds `nightly-${github.run_id}` and pushes it to ECR.
4. A temporary Amazon Linux EC2 instance is created for smoke testing.
5. The workflow SSHes into that instance, pulls the image from ECR, starts the container, and curls `/health` and `/api/health`.
6. If smoke tests pass, the workflow SSHes into the QA EC2 host and replaces the running `fur-connect` container.

## QA runtime model

- The bundled container listens on internal port `80`.
- The deploy script binds that container to `127.0.0.1:8080` on the host.
- Host nginx handles HTTP to HTTPS redirect and proxies to `127.0.0.1:8080`.
- Runtime app configuration comes from either:
  - `QA_APP_ENV` GitHub Secret, or
  - `/opt/fur-connect/qa.env` stored on the EC2 host

## Security notes

- No secrets are committed to this repo.
- AWS access uses GitHub Secrets because OIDC is out of scope for this account.
- Port `22` should be restricted to known operator or CI source ranges.
- RDS should only allow inbound traffic from the QA EC2 security group.
- The temporary test instance is always terminated, even if smoke tests fail.
