# AI workflow log

How Claude Code was used to build Sentinel. Updated after each phase.

## Phase 1: core service
- **Delegated to AI:** project scaffold (Gradle KTS, Spring Boot 3.4, Kotlin), Flyway V1, rules, scoring engine, JDBC repositories, API-key filter, controllers, unit and integration tests.
- **Reviewed:** rule semantics against SPEC section 7 (velocity counts stored events in the window plus the current one), idempotency (`ON CONFLICT DO NOTHING` plus re-read), shadow-mode behaviour.
- **Changed along the way:** Kotlin 1.9 to 2.0.21 (detekt 1.23.8 is compiled against 2.0); Testcontainers bumped to 1.21.4 because 1.20 cannot talk to Docker Engine 29 (the integration test was silently skipped until then).
- **Went wrong:** first integration test run was skipped, not failed (`disabledWithoutDocker`), so green tests hid a missing test. Caught by checking the skipped count.

## Phase 2: Docker and async path
- **Delegated to AI:** multi-stage Dockerfile, compose with LocalStack, queue/DLQ init script, `scripts/smoke-test.sh`.
- **Design choice:** one process consumes its own queue (Spring Cloud AWS `@SqsListener`); endpoint and credentials come from standard Spring env vars, so no code differs between LocalStack and AWS.
- **Added beyond spec:** `PUT /rules/{id}` returns `auditId` so the smoke test can prove the audit row exists without adding an endpoint. `alerts.event_id` is UNIQUE so the consumer is idempotent.

## Phase 3: CI
- **Delegated to AI:** `ci.yml` (terraform fmt/validate job, detekt + tests, image build, compose smoke test, report artifacts) and `terraform-plan.yml`.
- **Not verified:** the workflows have not run on GitHub yet (no remote configured), so the "green on main" gate and the README badge are still open.

## Phase 4: Terraform
- **Delegated to AI:** modules (`network`, `ecr`, `rds`, `sqs`, `ecs_service`, `monitoring`, `oidc`), `bootstrap` and `demo` stacks, `verify-teardown.ps1`, `kill-timer.ps1`.
- **Reviewed:** plan lists 36 resources and none of the banned types; secrets only via Secrets Manager `valueFrom`; state bucket name is passed at init so no account id is committed.
- **Went wrong:** an org SCP explicitly denies `ec2:DescribeAvailabilityZones` and `elasticloadbalancing:Describe*` for `sentinel-deployer`. AZ names are now a variable. The ELB denial also breaks `verify-teardown.ps1` and probably ALB management itself; not worked around, escalated to the user.

## Region correction (ap-southeast-1 to ap-southeast-2)
- **What went wrong:** the first drafts of `CLAUDE.md`/`SPEC.md` named `ap-southeast-1`, but the AWS-managed SCPs on this account only allow workload services in `ap-southeast-2`. Everything was built against the wrong region.
- **How it was found:** `terraform plan` failed with an explicit SCP deny on `ec2:DescribeAvailabilityZones`, and `verify-teardown.ps1` got the same deny on `elasticloadbalancing:Describe*`. The AI wrongly guessed the ALB itself might be blocked and asked the user; the user identified the real cause (region).
- **Fix:** region and AZ defaults changed to `ap-southeast-2` / `2a`, `2b` everywhere. `scripts/preflight.ps1` now makes one read-only call per service Terraform needs (15 of 15 pass in `ap-southeast-2`). Lesson: run the preflight before writing infrastructure, and treat an SCP deny as a signal to re-check region before assuming a service ban.
- **Also verified:** `kill-timer.ps1` fired on schedule in a 2-minute dummy run (destroy failed harmlessly because no backend was initialised, then the teardown check ran clean).

## Phase 5: first AWS session (ap-southeast-2)
- **Delegated to AI:** image build and push, `terraform apply`/`destroy`, kill timer, proof run, teardown check. The user approved the bootstrap apply and the demo session explicitly and took the console screenshots.
- **Result:** 36 resources up about 7 minutes after apply started, smoke test PASS on AWS in 21s, k6 343 requests with 0% failures (p95 499ms), destroy of 36 resources, `verify-teardown.ps1` clean. Default sizing was enough, so no escalation ADR.
- **Went wrong:** `proof-run.ps1` called `bash`, which on this laptop is a WSL stub with no distro, so the smoke step failed locally. Re-ran through Git Bash and pointed the script at it. The corrected script was not re-run end to end.

## Phase 7: documentation
- **Delegated to AI:** README (Mermaid diagram, showcase table, GCP-to-AWS mapping), three ADRs, runbook.
- **Reviewed:** claims were checked against the proof files (21s smoke test, 343 k6 requests, p95 499 ms, 36 resources). Cost is an estimate until Cost Explorer shows the real figure.
- **Left for the user:** console screenshots, Cost Explorer screenshot, setting the GitHub repo variables, confirming CI is green.

## OIDC gotcha: immutable subject claims
- **What went wrong:** the first `terraform-plan` run on a PR failed at `configure-aws-credentials` with `Not authorized to perform sts:AssumeRoleWithWebIdentity`. The role trust policies (written by the AI) matched the classic subject `repo:owner/name:pull_request`, but this repo uses GitHub's immutable subject (`repo:owner@<owner_id>/name@<repo_id>:pull_request`).
- **How it was found:** the repo variables were correct, so the AI read the live trust policy and ran `gh api repos/<owner>/<repo>/actions/oidc/customization/sub`, which returned `use_immutable_subject: true` and the ID-bearing prefix.
- **Fix (user-approved, since it changes IAM):** trust conditions now use exact `StringEquals` on `sub` (no wildcards) with `github_owner_id` and `github_repo_id` as module variables. The plan was exactly 2 in-place changes; bootstrap state was backed up outside the repo first (it is local-only). The PR plan run then went green.
- **Lesson:** check the repo's OIDC subject customization before writing trust policies. Also, the AI had assumed the classic subject format from memory and never tested the login path until a PR existed.
