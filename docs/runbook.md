# Runbook

All commands use profile `sentinel` and region `ap-southeast-2` only.

## Before anything

```powershell
aws sts get-caller-identity --profile sentinel --region ap-southeast-2
powershell -File scripts/preflight.ps1
```

Confirm the account ends in `2410` and the user is `sentinel-deployer`. If not, stop.

## Deploy (demo session)

1. Build and push the image to the `sentinel-app` ECR repo (log in with `aws ecr get-login-password`, then `docker build --platform linux/amd64` and `docker push`).
2. In `infra/demo`:
   ```bash
   export AWS_PROFILE=sentinel AWS_REGION=ap-southeast-2
   terraform init -reconfigure -backend-config="bucket=sentinel-tfstate-<account-id>"
   terraform apply
   ```
3. Immediately arm the kill timer: `powershell -File scripts/kill-timer.ps1 -Minutes 90`.
4. Wait for `http://<alb-dns>/actuator/health` to return 200 (about a minute after apply).
5. Run `scripts/smoke-test.sh http://<alb-dns>` with `API_KEY` set from the `sentinel/api-key` secret, then `scripts/proof-run.ps1` for scenarios and k6.

## Deploy through GitHub Actions (CD)

Run `deploy` (Actions tab, Run workflow, branch `main`). It builds and pushes the image, applies `infra/demo`, runs the smoke test, then always destroys and runs the teardown check, so no kill timer is needed. Set the repository secrets listed in the README first. If a run is cancelled or hangs, run `destroy` from `main`; if Terraform reports a held state lock, wait for the other run to finish, or `terraform force-unlock <id>` from a laptop after confirming nothing else is running. A red teardown check means resources are left: delete them and re-run `destroy`.

## Verify nothing is left (manual, any time, read-only)

Three equivalent ways; all list load balancers, target groups, RDS instances and snapshots, NAT gateways, Elastic IPs, ECS clusters, ENIs and VPCs tagged `Project=sentinel`, SQS queues and secrets, and print `RESULT: CLEAN` or exit 1:

1. **GitHub:** Actions tab, `verify-teardown`, Run workflow, branch `main`. The result is in the job summary.
2. **Laptop, PowerShell:** `powershell -File scripts/verify-teardown.ps1` (uses profile `sentinel`).
3. **Laptop or any Linux shell, bash:** `AWS_PROFILE=sentinel AWS_REGION=ap-southeast-2 scripts/verify-teardown.sh`.

Also look at Billing, Cost Explorer the next day: a clean check and a near-zero daily cost agree.

## Rollback

There is no blue/green. To roll back a bad image: push the previous image tag, then `terraform apply -var image_tag=<tag>` (the service replaces the task). If the stack itself is bad, destroy it (below) and redeploy.

## Teardown

```bash
cd infra/demo && terraform destroy
powershell -File scripts/verify-teardown.ps1     # must print RESULT: CLEAN
powershell -Command "Unregister-ScheduledTask -TaskName sentinel-kill-timer -Confirm:\$false"
```

Check Cost Explorer the next day.

## If the kill timer fails

The timer is a Windows scheduled task, so it does not run if the laptop is off or asleep at the deadline.

1. Run the teardown above by hand as soon as you notice.
2. If `terraform destroy` fails, read the error, delete the blocking resource in the console (usually a leftover ENI or a security group still in use), and re-run destroy.
3. If state is lost, delete by tag `Project=sentinel` in this order: ECS service, ALB and target group, RDS instance, SQS queues, secrets (`sentinel/`), then the VPC pieces.
4. Run `scripts/verify-teardown.ps1` until it is clean. A session is not finished before that.

Prevent it: keep the laptop awake and plugged in during a session, and confirm `Get-ScheduledTask sentinel-kill-timer` shows the expected next run time.

## Note: GitHub OIDC subject format

This repository uses GitHub's immutable OIDC subject, so tokens carry `repo:mini4141@<owner_id>/vie-sentinel@<repo_id>:<context>`. The IAM trust policies in `infra/modules/oidc` match that exact form (variables `github_owner_id` and `github_repo_id`). If the repo is recreated, renamed or transferred, the IDs change: look them up with `gh api repos/<owner>/<repo> --jq '.owner.id, .id'`, update the variables, and re-apply `infra/bootstrap`. Symptom of a mismatch: `Not authorized to perform sts:AssumeRoleWithWebIdentity` in the workflow log.
