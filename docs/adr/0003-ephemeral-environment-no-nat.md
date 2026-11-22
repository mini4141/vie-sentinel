# ADR 0003: Ephemeral environment and no NAT gateway

Status: accepted

## Context
This is a portfolio project, so cost control is a hard requirement. A NAT gateway costs about as much per hour as the rest of the demo stack combined, and an ALB, RDS instance and Fargate task bill while idle.

## Decision
- Split Terraform into a permanent, near-free `bootstrap` stack (state bucket, lock table, ECR, OIDC) and an ephemeral `demo` stack that is created for a proof run and destroyed.
- Use a VPC with two public subnets only: no NAT, no private subnets, no VPC endpoints. Tasks get public IPs; the task security group accepts traffic only from the ALB, and RDS accepts connections only from the task security group and is not publicly accessible.
- Arm a kill timer (destroy at T+90 minutes) and require `scripts/verify-teardown.ps1` to report zero leftovers before a session counts as finished.
- RDS uses `skip_final_snapshot = true`, `deletion_protection = false`, and no backups, so `terraform destroy` always succeeds.

## Alternatives
- **Private subnets plus NAT or VPC endpoints:** the production-correct layout, but it multiplies hourly cost and is out of scope for a one-hour demo.
- **Leave the stack running:** simplest to show, but an ongoing monthly bill.

## Consequences
- Not a production network design; documented as a trade-off, not an oversight.
- Application state is lost on every destroy, which is acceptable for a demo.
- Proof of the run lives in `docs/proof/`, because the environment itself will not exist.
