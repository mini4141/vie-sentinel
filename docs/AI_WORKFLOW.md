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
