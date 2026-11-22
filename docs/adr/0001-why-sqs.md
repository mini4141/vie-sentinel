# ADR 0001: SQS for the alert path

Status: accepted

## Context
`REVIEW` and `BLOCK` decisions must trigger follow-up work (store an alert, count it) without slowing the decision request. The project must show async messaging that runs identically locally and on AWS, and it must be cheap and fully destroyable.

## Decision
Use one standard SQS queue plus a dead-letter queue (`maxReceiveCount = 3`, 1 day retention). The app publishes after the decision is stored and consumes in the same process with Spring Cloud AWS `@SqsListener`. Endpoint and credentials come from standard Spring properties, so LocalStack and AWS run the same code.

## Alternatives
- **Kinesis, MSK:** stream semantics and per-hour cost we do not need; MSK and Kinesis are banned by the project rules.
- **SNS fan-out:** useful with several consumers; there is one.
- **In-process events or a DB outbox:** no messaging service to demonstrate and no DLQ behaviour.

## Consequences
- Publishing is best effort: a failed publish is logged and the decision stands.
- The consumer is idempotent (`alerts.event_id` is unique), because standard queues deliver at least once.
- Messages that fail three times land in the DLQ, which has a CloudWatch alarm.
