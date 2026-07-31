# ADR-004: ECS Fargate for Application Compute

## Status
Accepted

## Context
Per NFR-REL-2 and NFR-REL-3, the application must tolerate the loss of a single
compute instance without full service outage, recovering automatically without manual
intervention. DentalFlow's backend is a long-running FastAPI application handling both
live web requests and SQS message processing, not a short-lived, event-triggered
workload. This favors a container-based, always-on compute model over a function-based
one. Fargate removes the need to manage underlying servers ourselves, while still
giving us a continuously running process suited to this workload shape.

## Decision
Run the backend as an ECS Fargate service with the following configuration:

- **Minimum 2 tasks, one per Availability Zone.** Running only 1 task means losing
  that task, or its AZ, takes the application down entirely. 2 tasks across 2 AZs
  ensures at least one healthy task remains if either fails, satisfying NFR-REL-2.
  ECS monitors task health automatically and replaces a failed task without manual
  intervention, without needing a separate Auto Scaling Group construct (Fargate
  manages this at the service level).
- **Task size: 0.25 vCPU / 0.5 GB memory** to start, the smallest Fargate offers.
  DentalFlow's actual traffic (single practice, low volume) does not justify a larger
  reservation, and Fargate bills by what's reserved, not just used, so oversizing
  wastes cost per NFR-COST-1. This will be monitored and increased only if the
  container is observed hitting out-of-memory kills.
- **Application Load Balancer (ALB) from day one**, sitting in the public subnet,
  receiving inbound traffic and routing it to the ECS tasks in the private subnets.
  This is the mechanism referenced in ADR-001: inbound traffic to already-running tasks
  does not depend on the NAT Gateway, only outbound traffic does.

## Consequences

**Positive:** The application can lose one task or one entire AZ without going down,
directly satisfying NFR-REL-2. Starting with the smallest task size keeps cost minimal
while traffic is low, with a clear signal (OOM kills) for when to scale up.

**Negative (accepted tradeoff):** Running 2 tasks minimum, plus an ALB, means baseline
cost is higher than a single-task, no-load-balancer setup would be. This is accepted as
the minimum viable configuration for genuine fault tolerance, not an optional
production nicety.

**IAM permissions for Fargate (to be resolved during implementation):** ECS Fargate
tasks require IAM roles (a task execution role, and a task role for application
permissions to S3/SQS/SNS/Secrets Manager). Our current IAM user (dentalflow-dev) uses
PowerUserAccess, which explicitly denies IAM role creation, by design. We expect to
encounter an access-denied error when this module is planned or applied. The
resolution is a narrowly-scoped IAM policy permitting role creation, attachment, and
pass-role actions, restricted to resources named with a dentalflow- prefix, rather than
escalating to AdministratorAccess. This keeps the credential's blast radius bounded
even though its capability is being extended.

## Alternatives Considered
**AdministratorAccess**, as a shortcut past the IAM role-creation restriction. Rejected:
this removes the one meaningful boundary PowerUserAccess was chosen for (preventing
privilege escalation via a leaked credential), and does not reflect how real
organizations scope access for a new engineer. A narrowly-scoped addition is a small
amount of extra Terraform for a materially more defensible security posture.

**Lambda + API Gateway**, instead of ECS Fargate. Rejected: DentalFlow's backend is a
long-running, stateful-connection application (persistent DB connection pooling, SQS
polling loop), which fits a continuously running container better than a stateless,
time-limited function execution model. Lambda's per-invocation model and execution
time limits are a poor fit for a service expected to run continuously and hold state
like connection pools.
