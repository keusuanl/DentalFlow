# DentalFlow — Architecture & Data Flow

This describes the end-to-end technical flow from scan upload to lab notification and
order completion. See docs/adrs/ for the reasoning behind each technology choice
referenced here, and docs/architecture/requirements.md for the NFRs each step satisfies.

## Actors

- **Dentist (clinic user):** creates orders, uploads scans, views own clinic's order status.
- **Lab technician:** views assigned orders, downloads scans, updates fabrication status.

## Components

- **Frontend:** React + Vite, served to the browser.
- **Backend API:** FastAPI, running on ECS Fargate. Handles both live web requests and
  background SQS processing (see "Open Decision" below).
- **S3:** Private, encrypted bucket for scan file storage.
- **RDS PostgreSQL:** Order and patient-record metadata.
- **SQS (upload queue):** Durable buffer between S3 upload events and order-status updates.
- **SNS + SQS (notification fan-out):** Durable, fanned-out lab and clinic notification delivery.
- **Secrets Manager:** Database credentials, no secrets in code or env vars (NFR-SEC-5).

## Flow

1. **Dentist authenticates** into the frontend and fills in patient/case info (name,
   case type — aligner/partial denture, notes) and selects a scan file (STL/ZIP/PDF).

2. **Order creation (metadata first, before upload):** The frontend calls the FastAPI
   backend with the patient/case metadata. The backend:
   - Creates an order record in RDS with status `pending_upload`.
   - Generates a short-lived, scoped **S3 presigned URL** authorizing exactly one
     upload, to one specific object path, for a limited time window.
   - Returns the presigned URL to the frontend.
   This ordering ensures no orphaned S3 files exist without a corresponding record, and
   satisfies NFR-SEC-4 (least privilege) — the frontend is never issued standing AWS
   credentials, only a narrow, temporary, single-purpose permission.

3. **Direct upload to S3:** The frontend uploads the scan file directly to S3 using the
   presigned URL. The file's bytes never pass through the backend — this keeps the API
   lightweight and reduces the backend's exposure to large file transfer.

4. **S3 event → SQS (upload queue):** When the file lands in S3, an event notification
   is sent to an SQS queue: "a scan has arrived for order X." Using SQS here (rather than
   processing the event inline) means a transient failure to update the order status is
   retried rather than silently lost.

5. **Backend processes the upload event:** The backend consumes the SQS message, verifies
   the file arrived, and updates the order's status in RDS (e.g. `pending_upload` →
   `received`), storing the S3 object path for later retrieval by the lab.

6. **Notification fan-out (lab side):** Once the order status is updated, the backend
   publishes a message to an SNS topic containing the case ID, patient reference, and
   S3 path. SNS fans this out to an **SQS queue**, which durably holds the notification
   until a consumer (a lab-facing notification service/dashboard) processes it. Email
   notification is layered on top as a secondary, best-effort channel — not the sole
   or primary mechanism — satisfying NFR-REL-1 (a dropped notification must not be a
   silent failure).

7. **Lab team processes the case:** A lab technician opens the web app, sees only orders
   assigned to them (NFR-SEC-3), downloads the scan from S3, and updates status through
   fabrication stages (e.g. `in_fabrication` → `completed`). These updates go back
   through the same FastAPI backend into RDS.

8. **Clinic notified of completion:** Same SNS→SQS fan-out pattern as step 6, triggered
   on the `completed` status transition, notifying the originating clinic the appliance
   is ready.

## Summary (compressed)

Frontend -> FastAPI (ECS) -> RDS (order created, pending_upload) + presigned URL issued
Frontend -> S3 (direct upload via presigned URL)
S3 -> SQS (upload event) -> FastAPI worker -> RDS (status: received)
FastAPI worker -> SNS -> SQS (fan-out) -> notification consumer -> lab team (+ email, best-effort)
Lab team -> FastAPI (ECS) -> RDS (status updates through fabrication)
Status: completed -> SNS -> SQS (fan-out) -> clinic notification


## Open Decisions / Deferred Scope

- **Worker architecture:** the same FastAPI/ECS Fargate service currently handles both
  live web requests and SQS message processing (Option A — chosen for DentalFlow's
  scale; to be formalized in the ADR covering ECS design). Splitting into a separate
  worker service is the natural evolution path once volume grows or for the future
  multi-tenant CloudDent platform.
- **Edge protection (WAF, rate limiting):** deliberately out of scope for this flow.
  See NFR-SEC-7 and docs/adrs/0000-single-tenant-scope.md.
