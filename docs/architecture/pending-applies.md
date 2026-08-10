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

| infra/modules/rds | Yes - 45 total resources in full plan | Not yet applied | Multi-AZ PostgreSQL, credentials via random_password + Secrets Manager. Ready for a short apply-test-destroy cycle once the backend needs it, or can be tested standalone via terraform apply -target if desired. |

## 1b. Local Development Database (backend phase)

Backend development uses a disposable local Postgres container, not RDS, to avoid
idle AWS cost while iterating on application code. RDS (ADR-005) remains destroyed
and will be applied again only for a dedicated deploy-test-destroy cycle once the
backend is functional enough to validate against real infrastructure.

| Component | Status | Notes |
|---|---|---|
| Local Postgres (Docker) | Running | `docker run --name dentalflow-postgres postgres:16`, port 5432, disposable, local-only credentials, never reused for real environments |
| Alembic | Configured, 1 migration applied | `env.py` reads `DATABASE_URL` from `app.core.config.settings`, not `alembic.ini`, to keep secrets single-sourced |
| Schema state | `users`, `orders` tables created | Migration `5aad5c9b6c7b`, reviewed manually against data-model.md before applying |


### When to update this section
- Before any future apply, note the date here.
- Before ending a work session, confirm nothing is left live (`terraform plan` should
  show 0 to add if starting from empty state, or check AWS Billing Dashboard directly).

## 2. Pending ADRs (documentation debt)

| ADR | Status | Notes |
|---|---|---|
| IAM scoping strategy for local dev credentials | Not written | Covers why PowerUserAccess was chosen over AdministratorAccess, why the narrow dentalflow-role-management policy exists, why it must be attached manually via root or console (self-privilege-escalation prevention), and the full discovered permission list (CreateRole, ListRolePolicies, ListAttachedRolePolicies, ListInstanceProfilesForRole, and others) with the real incident story as justification. Referenced informally in ADR-004. Deserves its own numbered ADR since it is a standalone, recurring security decision. |


| psycopg2 vs psycopg3 driver choice | Not written | Switched from psycopg2-binary to psycopg[binary] (psycopg3) after psycopg2 had no prebuilt wheel for Python 3.14. Also documents the subsequent decision to recreate the dev venv on Python 3.12 rather than continue chasing wheel availability across the dependency tree — the actual root cause was running a bleeding-edge CPython release with immature ecosystem support, not any single package. Real incident, both decisions made deliberately with reasoning, not just "whatever worked." |


### When to update this section
- Add a row whenever a real decision gets made and implemented in code or console
  before its ADR is written.
- Remove the row once the ADR is written and committed, replacing it with a
  cross-reference in the relevant module or ADR instead.
