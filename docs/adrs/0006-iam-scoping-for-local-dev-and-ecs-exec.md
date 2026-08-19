# ADR-0006: IAM Scoping for Local Dev Credentials and ECS Exec

## Status
Accepted

## Context
The local dev IAM user (dentalflow-dev) uses PowerUserAccess, which grants broad
service access but explicitly denies IAM role creation and modification, by design -
this is what prevents a leaked local credential from being used to grant itself
arbitrary new permissions (privilege escalation).

Two separate needs surfaced during the project that PowerUserAccess alone could not
satisfy:

1. ECS Fargate (ADR-0004) requires IAM roles (task execution role, task role) to be
   created via Terraform. Applying the ecs module with only PowerUserAccess produced
   an access-denied error on role creation, as expected.
2. Running Alembic migrations against real RDS (VPC-isolated, unreachable from a local
   machine) required ECS Exec - opening an interactive shell inside a running Fargate
   task over SSM. This requires the task's own IAM role (not the local dev user) to
   have SSM messaging permissions.

## Decision
Two narrowly scoped additions were made rather than escalating to AdministratorAccess:

1. A custom IAM policy permitting role creation, attachment, and pass-role actions,
   restricted to resources named with a `dentalflow-` prefix, attached to the
   dentalflow-dev user. This was applied manually via the AWS root/console, not via
   Terraform under the same dentalflow-dev credential - a credential cannot be used to
   grant itself new permissions it doesn't already have, so this step is inherently a
   manual, out-of-band action.
2. The AWS managed policy `AmazonSSMManagedInstanceCore` attached to the ECS task role
   (not the task execution role), enabling `aws ecs execute-command` for one-off
   operational tasks like running migrations against VPC-isolated RDS.

## Consequences

**Positive:** The dentalflow-dev credential's blast radius stays bounded even as its
capability grows - it can only create/manage roles and resources within the
`dentalflow-` naming prefix, not arbitrary IAM entities. This reflects how real
organizations scope access for a new engineer rather than granting broad admin rights
out of convenience. ECS Exec provides genuine operational capability (shell access into
a running container over an encrypted channel, no bastion host or exposed ports needed)
using an existing, already-deployed resource rather than new infrastructure.

**Negative (accepted tradeoff):** `AmazonSSMManagedInstanceCore` is broader than the
minimal set of `ssmmessages:*` actions ECS Exec strictly requires - a fully
least-privilege implementation would use a custom, narrower policy. Accepted for now
to avoid piecemeal IAM policy sprawl; this is the natural next refinement once the
task role's full permission surface (S3, SQS, SNS, Secrets Manager) is finalized, at
which point one comprehensive least-privilege task role policy should replace both this
and the deferred S3/SQS/SNS permissions noted in ADR-0004.

## Alternatives Considered
**AdministratorAccess for the local dev user**, as a shortcut past both restrictions.
Rejected for the same reasoning as ADR-0004: removes the one meaningful boundary
PowerUserAccess was chosen for, and does not reflect real-world credential scoping
practice.

**A bastion host or VPN** for reaching VPC-isolated RDS, instead of ECS Exec. Rejected:
both require additional infrastructure (an EC2 instance or VPN gateway) for a need
already satisfiable via a resource that already exists and already has network access
to RDS - the running ECS task itself.
