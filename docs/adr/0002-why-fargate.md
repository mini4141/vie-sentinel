# ADR 0002: ECS Fargate rather than EC2 or Lambda

Status: accepted

## Context
The service is a long-running Spring Boot app with a connection pool to Postgres and a queue listener. It is deployed for one to three hours and then destroyed.

## Decision
Run one task on ECS Fargate (0.5 vCPU / 1 GB, x86_64) behind an ALB. The Phase 5 session confirmed the size: startup was well inside the 120 s health-check grace period, all health checks passed, and the k6 run showed p95 of 499 ms with no errors, so no escalation was needed.

## Alternatives
- **EC2:** banned by the project rules, and it adds patching and capacity management for no benefit here.
- **Lambda:** JVM cold starts, connection pooling against RDS, and a long-lived SQS listener fit poorly.
- **EKS:** far more cost and setup than a one-service demo justifies.

## Consequences
- Tasks get public IPs so they can reach ECR, Secrets Manager and SQS without a NAT (see ADR 0003); security groups restrict inbound traffic to the ALB.
- Single task and no autoscaling, by design. Deployments use min healthy 0 / max 100 percent for fast replacement.
- Step up one size (1 vCPU / 2 GB) only on evidence, recorded in a new ADR.
