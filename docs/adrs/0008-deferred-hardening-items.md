# ADR-0008: Deferred Hardening Items

## Status
Accepted (as a deliberate, tracked scope decision)

## Context
Several smaller hardening items surfaced during the backend and deployment phases that
do not individually warrant a full ADR - each is a known gap with an obvious, already
understood fix, deferred consciously to keep session scope manageable rather than
discovered as an oversight later. Grouped here rather than left as scattered notes.

## Deferred Items

**1. Secrets Manager integration for the ECS task definition.**
`JWT_SECRET` and `DATABASE_URL` are currently injected into the ECS task definition as
plain (Terraform `sensitive = true`, but not encrypted at rest in state or the task
definition itself) environment variables via `terraform.tfvars`, gitignored locally.
ADR-0005 already established that RDS credentials live in Secrets Manager; the task
definition does not yet retrieve them from there. Fix: use the ECS task definition's
`secrets` block (not `environment`), referencing the existing `dentalflow-dev-db-credentials`
secret's individual JSON keys, plus a new Secrets Manager entry for `JWT_SECRET`.
Deliberately deferred to get a working deployment first, verified end to end, before
adding this layer.

**2. Non-root container user.**
The Dockerfile's base image (`python:3.12-slim`) runs the application as `root` by
default - confirmed via `whoami` during an ECS Exec session. No explicit `USER`
instruction was added. Fix: create a non-root user in the Dockerfile and switch to it
before the `CMD` instruction. Standard container security practice; not yet applied.

**3. DLQ-aware retry logic in the SQS consumer.**
`sqs_consumer.py` deletes every received message unconditionally in a `finally` block,
regardless of whether processing succeeded. ADR-0003 describes DLQ-based retry for
genuine failures (e.g. RDS temporarily unavailable mid-processing); this implementation
does not yet distinguish "processed successfully" from "failed, should be retried via
natural redelivery and eventual DLQ routing." Acceptable at current single-tenant,
low-volume scope. Verified live and working under normal conditions; not yet tested
under simulated failure.

## Consequences
Tracking these together, rather than as individual ADRs, keeps ADRs reserved for
genuine decisions with real trade-offs and alternatives, consistent with this project's
own principle (see ADR template guidance referenced across ADR-0000 through ADR-0007).
Each item here has one clear, already-understood fix - the open question is
prioritization and timing, not which approach to take.

## When to revisit
Before considering the backend "production-shaped" rather than "portfolio-complete" -
none of these block a working demo or a technically sound review of the project's
architecture, but all three would be expected in a real production deployment.
