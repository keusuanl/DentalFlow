# DentalFlow - Data Model

Defines the core database tables backing the FastAPI application, and the API
endpoints that operate on them. See docs/architecture/data-flow.md for the
end-to-end request flow these tables and endpoints support, and
docs/architecture/requirements.md for the NFRs referenced below.

## users

Stores both dentists and lab technicians. Role determines what a user can do,
enforced via a JWT issued at login (see Authentication section below).

| Field | Type | Notes |
|---|---|---|
| id | UUID, primary key | Not sequential, avoids order/user enumeration by guessing IDs |
| email | VARCHAR(255), unique | Login identifier |
| password_hash | VARCHAR(255) | Bcrypt hash. Passwords are hashed, never encrypted, meaning they cannot be reversed even by the system itself |
| role | VARCHAR(50) | "dentist" or "lab_tech". Drives every permission check |
| full_name | VARCHAR(255) | Display name |
| is_active | BOOLEAN, default true | Allows disabling an account without deleting it |
| created_at | TIMESTAMP, default now | |

## orders

One row per scan/case submitted by a dentist.

| Field | Type | Notes |
|---|---|---|
| id | UUID, primary key | |
| patient_name | VARCHAR(255) | |
| patient_dob | DATE | |
| patient_gender | VARCHAR(50) | |
| case_type | VARCHAR(100) | e.g. aligners, partial denture, crown |
| notes | TEXT | Dentist's notes for the lab |
| s3_object_key | VARCHAR(512) | Path in S3, pattern: scans/{order_id}/{filename}, per ADR-002 |
| status | VARCHAR(50) | See status lifecycle below. Enforced in application code, not a DB-level enum, to keep adding new statuses simple as the project evolves |
| dentist_id | UUID, foreign key -> users.id | Set from the authenticated session at creation time, never a free-text field, per NFR-SEC-1 |
| assigned_lab_tech_id | UUID, nullable, foreign key -> users.id | NULL until a lab tech claims the order |
| created_at | TIMESTAMP, default now | |
| updated_at | TIMESTAMP, default now, auto-updates | |
| completed_at | TIMESTAMP, nullable | Set only when status reaches completed |

### Status lifecycle

**pending_upload -> received -> in_fabrication -> completed**

- pending_upload: order created, presigned URL issued, file not yet confirmed in S3
- received: set automatically by the backend's SQS consumer once S3 confirms the file
  arrived (ADR-002, ADR-003). No human action triggers this transition.
- in_fabrication: set when a lab tech claims the order. This is also the point
  assigned_lab_tech_id is set, from the authenticated session, not user input.
- completed: set by the lab tech once fabrication is done. Triggers the clinic
  notification via the SNS -> SQS fan-out pattern (ADR-003).

## Role-based access

Enforced via role-based checks reading the JWT's role claim before an endpoint's
logic runs, per NFR-SEC-2 and NFR-SEC-3.

| Endpoint | Dentist | Lab tech |
|---|---|---|
| POST /login | yes | yes |
| POST /orders | yes | no |
| GET /orders | yes, own clinic's orders | yes, unassigned + own assigned orders only |
| GET /orders/{id} | yes, own clinic's orders | yes, if assigned or unassigned |
| PATCH /orders/{id} | no | yes, status and assignment only, never patient fields |
| GET /orders/{id}/download-url | no | yes |
| GET /health | n/a, infrastructure only | n/a |

Lab tech assignment: DentalFlow has one internal lab team, not multiple labs to
route between (see ADR-000, single-tenant scope). No automated routing logic is
needed. An order becomes visible to all lab techs once status reaches received;
whichever lab tech acts on it first is assigned via the same PATCH call that moves
status to in_fabrication. A dedicated ops/coordinator role overseeing multi-lab
routing is out of scope for DentalFlow and is a candidate feature for CloudDent.

## Authentication

- Passwords are hashed with bcrypt, never stored in plaintext or encrypted
  reversibly.
- Login failures return a single, generic "invalid credentials" message regardless
  of whether the email or password was wrong, to prevent user enumeration
  (OWASP Identification and Authentication Failures).
- On successful login, a JWT is issued containing the user's id and role. The JWT
  is signed, not encrypted; its contents are readable but cannot be forged, since
  any tampering invalidates the signature.
- Protected endpoints verify the JWT's signature and read its role claim before
  running any business logic, rejecting with 403 if the role is not permitted.
