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


## 1c. Backend Auth Flow (backend phase)

First fully working, end-to-end tested slice of the API: registration, login, JWT
issuance, and RBAC scaffolding. Verified against real requests (curl), not just code
review — including direct psql inspection of inserted rows.

| Component | Status | Notes |
|---|---|---|
| POST /auth/register | Working | Bcrypt hashing confirmed via psql, duplicate email returns clean 400 (fixed from unhandled 500/IntegrityError) |
| POST /auth/login | Working | JWT issued correctly; anti-enumeration confirmed both directions (wrong password / unknown email return identical 401) |
| get_current_user / require_role | Written, not yet used by a protected route | Next: wire into orders.py |
| GET /health | Working | No auth required, infra-only per data-model.md |

### Known gap
Docker Postgres container does not persist across WSL2/Docker daemon restarts
automatically (no --restart policy set). Start of next session, run `docker start
dentalflow-postgres` (not `docker run`) before testing anything — confirmed this
already caused one 500 error this session, root-caused via `docker ps -a`.



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



## 3. Project Phase Decision: Infra Lifecycle Policy Change

**Decision (2026-08-11):** Moving forward, infrastructure will be applied and left
running for the remainder of active backend development, rather than continuing the
apply-test-destroy-per-session discipline used throughout the infra phase.

**Reasoning:** The original discipline existed because infra was being validated in
isolation, module by module, with no real integration to test against yet. That
context no longer applies — the backend now needs to exercise S3, SQS, SNS, and RDS
together, repeatedly, over extended sessions (presigned URLs, a long-running SQS
consumer, SNS fan-out). Destroying and reapplying after each session would reintroduce
setup toil with no corresponding learning benefit, and would prevent the kind of
long-running, realistic integration testing this stage actually requires.

**Accepted tradeoff:** Real, ongoing hourly cost from Multi-AZ RDS (ADR-005) and the
NAT Gateway (ADR-001), no longer bounded by short apply-test-destroy windows. Considered
acceptable at this project stage. Candidate follow-up: a CloudWatch billing alarm, or
at minimum a habit of periodically checking the AWS Billing Dashboard, per NFR-OBS-2/3 —
not yet implemented.

**Scope:** This does not change the ADR-000 single-tenant scope decision, nor any
individual ADR's technical reasoning (Multi-AZ, shared NAT Gateway, etc.) — only when
resources are destroyed, not what was decided about how they're built.

### When to revisit
- Once the backend's S3/SQS/SNS/RDS integration work is complete and stable, revert to
  apply-test-destroy discipline for any further isolated testing, or move to a final
  teardown once the project moves into portfolio/demo-only mode.



## 4. Incident: Secrets Manager deletion recovery window blocks re-apply

**What happened (2026-08-13):** Re-applying full infra after the earlier destroy cycle
failed on `aws_secretsmanager_secret.db_credentials` — AWS Secrets Manager schedules
deleted secrets for a recovery window (default 30 days) rather than deleting them
immediately, and refuses to create a new secret with the same name while the old one
is still in that window.

**Root cause:** The original `terraform destroy` (2026-08-04) scheduled the secret for
deletion but didn't remove it immediately. This is Secrets Manager's built-in recovery
protection working as designed, not a bug.

**Fix:** `aws secretsmanager delete-secret --secret-id <name> --force-delete-without-recovery`
to free the name immediately, then re-run `terraform apply` — Terraform resumed from
state and only recreated the 2 missing resources (secret + secret version), not all 45.

**Lesson for future destroys:** any future `terraform destroy` involving Secrets Manager
will leave this same trap for the next apply unless force-delete is used at destroy time,
or the recovery window is intentionally shortened in the resource config. Worth deciding
if this is worth adding to ADR-005 as a known operational quirk.



## 5. Session checkpoint: presigned URL code written, not yet live-tested

Full infra re-applied (45 resources), all AWS outputs captured. Discovered RDS is
correctly unreachable from outside the VPC (security group scoped to ECS tasks only) —
confirms ADR-005's isolation is real, but means real-RDS testing now requires the
backend to actually run on ECS, not locally. Local dev continues against Docker
Postgres in the meantime.

S3 presigned upload URL code is written (`s3_service.py`, wired into `create_order`)
but NOT YET TESTED against the real bucket. Next session: test POST /orders live,
confirm presigned URL works with a real curl upload, verify object lands in S3.

Remaining before Docker/ECS: GET /orders/{id}/download-url, SQS consumer, SNS publish.


## 6. S3 presigned upload flow: verified live (2026-08-14)

POST /orders now generates a real presigned S3 PUT URL, tested end to end:
order created -> presigned URL returned -> curl -T upload directly to S3 -> confirmed
via `aws s3 ls` that the object landed at the correct scans/{order_id}/{filename} path.
No longer a known gap.


## 7. SQS consumer: verified live, with a documented simplification (2026-08-14)

Background asyncio task (FastAPI lifespan) polls the upload SQS queue via boto3 in a
threadpool (asyncio.to_thread), avoiding blocking the event loop. Verified end to end:
uploaded a real file via presigned URL, confirmed status auto-transitioned
pending_upload -> received with no manual PATCH call, within ~10-20s of upload.

**Known simplification, not yet hardened:** messages are deleted from the queue
unconditionally in a finally block, regardless of processing outcome. ADR-003 describes
DLQ-based retry for genuine failures (e.g. RDS unavailable mid-processing) — this
implementation does not yet distinguish "processed successfully" from "failed, should
retry via redelivery + DLQ." Acceptable for current single-tenant, low-volume scope;
worth hardening if this pattern carries into CloudDent.
