# Project Tracking - Pending Applies & Documentation Debt

## 1. Terraform Apply History

All four core infrastructure modules were fully applied and live-tested on 2026-08-03,
confirmed working end to end (ALB served the placeholder nginx page through the full
stack: VPC, NAT, security groups, ECS Fargate, IAM roles), then destroyed the same
session to avoid ongoing cost. Currently NOTHING is live in AWS.

| Module | Validated (plan) | Ever applied | Currently live | Notes |
|---|---|---|---|---|
| infra/modules/networking | Yes | Yes (2026-08-03) | No, destroyed | 14 resources, confirmed working |
| infra/modules/s3 | Yes | Yes (2026-08-03) | No, destroyed | 5 resources, confirmed working |
| infra/modules/sqs_sns | Yes | Yes (2026-08-03) | No, destroyed | 8 resources, confirmed working |
| infra/modules/ecs | Yes | Yes (2026-08-03) | No, destroyed | 12 resources, confirmed working end to end via live ALB test |

### When to update this section
- Before any future apply, note the date here.
- Before ending a work session, confirm nothing is left live (`terraform plan` should
  show 0 to add if starting from empty state, or check AWS Billing Dashboard directly).

## 2. Pending ADRs (documentation debt)

| ADR | Status | Notes |
|---|---|---|
| IAM scoping strategy for local dev credentials | Not written | Covers why PowerUserAccess was chosen over AdministratorAccess, why the narrow dentalflow-role-management policy exists, why it must be attached manually via root or console (self-privilege-escalation prevention), and the full discovered permission list (CreateRole, ListRolePolicies, ListAttachedRolePolicies, ListInstanceProfilesForRole, and others) with the real incident story as justification. Referenced informally in ADR-004. Deserves its own numbered ADR since it is a standalone, recurring security decision. |

### When to update this section
- Add a row whenever a real decision gets made and implemented in code or console
  before its ADR is written.
- Remove the row once the ADR is written and committed, replacing it with a
  cross-reference in the relevant module or ADR instead.
