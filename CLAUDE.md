# Sentinel: project rules for Claude Code

Sentinel is a real-time fraud detection service (Kotlin, Spring Boot 3, Postgres) deployed to AWS with Terraform. It is a portfolio project. It is deployed for 1-3 hours to capture proof, then destroyed. Cost control is a hard requirement.

## AWS guardrails (non-negotiable)

- Use ONLY the AWS profile `sentinel` (`--profile sentinel` or `AWS_PROFILE=sentinel`).
- Use ONLY region `ap-southeast-2`. Never create or query resources in any other region, except IAM, which is global. The project is restricted by AWS-managed SCPs to its selected region; `us-east-1` and `us-west-2` do not allow workload services.
- Before any `terraform apply`, run `aws sts get-caller-identity --profile sentinel` and confirm the account ID ends with `2410` and the user is `sentinel-deployer`. If not, stop.
- HARD BANS (never create, no exceptions without the user's explicit approval): NAT Gateways, standalone Elastic IPs, Multi-AZ RDS, EC2 instances, OpenSearch, ElastiCache, MSK, Kinesis, VPC endpoints, Route 53 hosted zones, WAF, or more than 1 ECS task.
- Allowed in the demo stack: VPC with public subnets, security groups, 1 ALB, ECS Fargate (1 task), RDS Postgres single-AZ, 1 SQS queue plus DLQ, CloudWatch logs (retention 3 days), CloudWatch alarms, SNS topic, Secrets Manager, IAM roles.
- SIZING IS A RECOMMENDATION, NOT A LIMIT. Start from the defaults in `SPEC.md` section 4a (Fargate 0.5 vCPU / 1 GB, RDS `db.t4g.micro`). If real evidence shows they are not enough (OOM kills, failing health checks, unacceptable startup time, DB connection or CPU exhaustion), step up ONE size at a time, record the evidence and the change in `docs/adr/`, and tell the user the new hourly cost. Never jump to large sizes "to be safe".
- Set `skip_final_snapshot = true` and `deletion_protection = false` on the demo RDS so `terraform destroy` works.
- Set an ECR lifecycle policy to keep at most 3 images.
- Never print, log, echo or commit AWS credentials, `~/.aws/credentials`, `.env` files or `*.tfvars`. Never read the credentials file.
- Do not modify IAM users, access keys, billing, budgets or anything outside resources named with the `sentinel-` prefix.
- Tag every resource: `Project=sentinel`, `Env=demo`, `Ephemeral=true`.

## Two Terraform stacks

- `infra/bootstrap/`: permanent and cheap. S3 state bucket (versioned), DynamoDB lock table (on-demand), ECR repository, GitHub OIDC provider and deploy role. Applied once.
- `infra/demo/`: ephemeral. VPC, ALB, ECS, RDS, SQS, monitoring. Created and destroyed on every demo run.

## Demo run procedure

1. Confirm the identity check above.
2. `terraform apply` in `infra/demo/`.
3. Start the kill timer: schedule a destroy at T+90 minutes (`scripts/kill-timer.ps1`) so a forgotten session cannot keep running.
4. Wait for ALB health checks to pass.
5. Run `scripts/proof-run.ps1`: scripted scenarios (ALLOW, BLOCK, REVIEW), a short k6 load test, and save outputs to `docs/proof/` with timestamps.
6. Capture screenshots or ask the user to capture them (ECS, RDS, CloudWatch).
7. `terraform destroy` in `infra/demo/`.
8. Run `scripts/verify-teardown.ps1`. It must list and expect ZERO of the following in ap-southeast-2: load balancers, RDS instances and snapshots, NAT gateways, Elastic IPs, ECS clusters, running tasks, and ENIs tagged `Project=sentinel`. If anything is left, delete it and rerun the check.
9. Tell the user to check Cost Explorer the next day.

A session is NOT finished until step 8 passes. If a command fails midway, the next action is to destroy and verify, not to debug while resources run.

## Code conventions

- Kotlin, Spring Boot 3, Gradle Kotlin DSL, Java 21.
- Package layout: `api`, `rules`, `engine`, `persistence`.
- Each fraud rule implements `Rule` and has unit tests. New rules support shadow mode (log only).
- Flyway migrations in `src/main/resources/db/migration`. Never edit an applied migration.
- Tests: JUnit 5 plus Testcontainers for Postgres. Run `./gradlew test` before every commit.
- Lint with detekt and ktlint. Keep them passing.
- Events must be handled idempotently (idempotency key per event).

## Working style

- `SPEC.md` is the source of truth for requirements, phases and acceptance gates. Read it at the start of every session and work on one phase at a time, in order.
- Prioritise technology breadth (Docker, Terraform, CI/CD, AWS) over business edge cases. Keep tests light: a few unit tests, one integration test, and the end-to-end smoke test `scripts/smoke-test.sh`. Do not add extra rules, endpoints or exhaustive tests.
- Everything must work and be validated locally (Docker Compose plus LocalStack) before any `terraform apply`. `terraform plan` is allowed earlier.
- Stop and show the user the Terraform plan and wait for approval before the first apply.
- Make small commits with clear messages. Do not commit secrets or Terraform state.
- Record meaningful decisions in `docs/adr/`. Keep `docs/AI_WORKFLOW.md` updated with what was delegated to AI, what was reviewed, and what was changed by hand.
- If a request would break a guardrail above, stop and ask the user.