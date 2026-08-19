# DentalFlow, Architecture & Data Flow

This describes the end to end technical flow from scan upload to lab notification and
order completion. See docs/adrs/ for the reasoning behind each technology choice
referenced here, and docs/architecture/requirements.md for the NFRs each step satisfies.

## Actors

- **Dentist (clinic user), calling the API directly:** creates orders, uploads scans, views own clinic's order status.
- **Lab technician, calling the API directly:** views assigned orders, downloads scans, updates fabrication status.

There is no frontend. DentalFlow is consumed directly via its documented API, using
curl and standard terminal tooling, see docs/architecture/api-walkthrough.md for the
full set of real, working requests covering every flow described below. This is a
deliberate scope decision, see ADR-0009.

## Components

- **Backend API:** FastAPI, running on ECS Fargate. Handles both live web requests and
  background SQS processing (see "Open Decision" below).
- **S3:** Private, encrypted bucket for scan file storage.
- **RDS PostgreSQL:** Order and patient record metadata.
- **SQS (upload queue):** Durable buffer between S3 upload events and order status updates.
- **SNS + SQS (notification fan-out):** Durable, fanned out lab and clinic notification delivery.
- **Secrets Manager:** Database credentials, no secrets in code or env vars (NFR-SEC-5).

## Flow

1. **Dentist authenticates** against the API and submits patient and case info (name,
   case type, aligner or partial denture, notes) along with the filename of the scan
   file to be uploaded (STL, ZIP, or PDF).

2. **Order creation, metadata first, before upload:** The client calls the FastAPI
   backend with the patient and case metadata. The backend:
   - Creates an order record in RDS with status `pending_upload`.
   - Generates a short lived, scoped **S3 presigned URL** authorizing exactly one
     upload, to one specific object path, for a limited time window.
   - Returns the presigned URL in the same response.
   This ordering ensures no orphaned S3 files exist without a corresponding record, and
   satisfies NFR-SEC-4, least privilege, the client is never issued standing AWS
   credentials, only a narrow, temporary, single purpose permission.

3. **Direct upload to S3:** The client uploads the scan file directly to S3 using the
   presigned URL, typically via `curl -T`. The file's bytes never pass through the
   backend, this keeps the API lightweight and reduces the backend's exposure to large
   file transfer.

4. **S3 event to SQS, upload queue:** When the file lands in S3, an event notification
   is sent to an SQS queue, "a scan has arrived for order X." Using SQS here, rather
   than processing the event inline, means a transient failure to update the order
   status is retried rather than silently lost.

5. **Backend processes the upload event:** A background task running inside the same
   FastAPI process polls the upload queue, verifies the file arrived, and updates the
   order's status in RDS (`pending_upload` to `received`), storing the S3 object path
   for later retrieval by the lab.

6. **Notification fan out, lab side:** Once the order status is updated, the backend
   publishes a message to an SNS topic containing the order ID, patient name, and event
   type. SNS fans this out to an **SQS queue**, which durably holds the notification
   until a consumer processes it, satisfying NFR-REL-1, a dropped notification must not
   be a silent failure.

7. **Lab team processes the case:** A lab technician calls the API, sees only orders
   that are unassigned or assigned to them (NFR-SEC-3), downloads the scan from S3 via
   a presigned download URL, and updates status through fabrication stages
   (`in_fabrication` to `completed`).

8. **Clinic notified of completion:** Same SNS to SQS fan out pattern as step 6,
   triggered on the `completed` status transition.

## Summary, compressed

Client -> FastAPI (ECS) -> RDS (order created, pending_upload) + presigned URL issued
Client -> S3 (direct upload via presigned URL)
S3 -> SQS (upload event) -> FastAPI background poller -> RDS (status: received)
FastAPI -> SNS -> SQS (fan-out) -> notification queue, ready for a consumer
Lab team -> FastAPI (ECS) -> RDS (status updates through fabrication)
Status: completed -> SNS -> SQS (fan-out) -> clinic notification

## Open Decisions / Deferred Scope

- **Worker architecture:** the same FastAPI/ECS Fargate service currently handles both
  live web requests and SQS message processing (Option A, chosen for DentalFlow's
  scale, per ADR-0004). Splitting into a separate worker service is the natural
  evolution path once volume grows, or for the future multi-tenant CloudDent platform.
- **Edge protection (WAF, rate limiting):** deliberately out of scope for this flow.
  See NFR-SEC-7 and docs/adrs/0000-single-tenant-scope.md.
- **Frontend:** deliberately out of scope, see ADR-0009.
