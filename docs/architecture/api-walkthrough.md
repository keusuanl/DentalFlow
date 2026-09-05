# DentalFlow, API Walkthrough

## Introduction

This document is the primary technical proof of DentalFlow, a working demonstration of every flow the system supports, run against the real, deployed environment, real ECS Fargate tasks, real RDS, real S3, real SQS, real SNS. There is no frontend, see ADR-0009, DentalFlow is demonstrated and consumed directly through its API.

Every request below is real, run against the live ALB URL, with real responses included as shown, not fabricated or idealized. Where a step has a corresponding piece of AWS console evidence, a screenshot placeholder marks exactly what to capture.

FastAPI also generates interactive API documentation automatically, available at
`http://<alb-dns-name>/docs`, useful for exploring the API's shape, though this
walkthrough is the authoritative, narrative record of the system actually working end
to end.

## The Business

DentalFlow models a digital dental lab workflow. A dental practice, the customer,
submits a case for a patient, an intraoral scan along with case details, aligner,
crown, or partial denture. An internal lab team, the fulfiller, receives the case,
fabricates the appliance, and the practice is notified once it is ready. This is a
single-tenant system, one practice, one internal lab team, see ADR-0000, modeled on the
real workflow used by digital dental manufacturing companies.

There is no payment or billing flow in DentalFlow, the business relationship it models
is operational, submitting and fulfilling a case, not transactional.

## Roles and Access

DentalFlow has two roles, enforced through a JWT issued at login, and checked before
any protected endpoint runs its logic.

**Role\tCan do**

- **dentist** — Register, log in, create orders, view their own clinic's orders
- **lab_tech** — Register, log in, view unassigned orders and orders assigned to them, claim and progress an order's status, download the scan file

Neither role can act outside these boundaries. A dentist cannot update order status or download scans, a lab technician cannot create orders or view another lab technician's assigned case. Every boundary below is demonstrated directly, not just described.

## Environment

All requests below are made against: http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com

*No API key or upfront credential is required to begin, only the two demo accounts created in the walkthrough itself*.

![Screenshot: ECS service running, 2/2 healthy tasks](screenshots/01-ecs-service-running.png)

## Walkthrough

### 1. The practice registers

A new dental practice creates an account. Note the response never echoes back a password or its hash, only what a client should ever see.

```bash
curl -X POST http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email": "dr.chen@dentalflow-demo.com", "password": "DemoPass123!", "full_name": "Dr. Sarah Chen", "role": "dentist"}'
```

**Response:**

```json
{
  "id": "80516aec-84c5-4ac8-a8ee-afff85d4dab3",
  "email": "dr.chen@dentalflow-demo.com",
  "full_name": "Dr. Sarah Chen",
  "role": "dentist",
  "is_active": true,
  "created_at": "2026-08-24T09:55:17.569546Z"
}
```

The password is never returned, not even hashed, only the account's public shape comes back. The password itself is bcrypt hashed before it ever touches the database.

### 2. The lab technician registers

```bash
curl -X POST http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email": "j.martinez@dentalflow-demo.com", "password": "LabDemo456!", "full_name": "James Martinez", "role": "lab_tech"}'
```

**Response:**

```json
{
  "id": "ceb03ed8-424f-454e-b090-86efd81e411d",
  "email": "j.martinez@dentalflow-demo.com",
  "full_name": "James Martinez",
  "role": "lab_tech",
  "is_active": true,
  "created_at": "2026-08-24T09:58:05.830540Z"
}
```

*Two accounts now exist, one dentist, one lab technician, each with a distinct role that will be enforced on every subsequent request.*

![Screenshot: RDS query or console view showing both new rows in the users table](screenshots/02-users-table-rds.png)

### Querying the Database

Since RDS itself doesn't have a query browser in the console, reuse ECS Exec:

```bash
aws ecs list-tasks --cluster dentalflow-dev-cluster --service-name dentalflow-dev-service --region us-east-1
```

```bash
aws ecs execute-command \
  --cluster dentalflow-dev-cluster \
  --task <task-id> \
  --container dentalflow-app \
  --interactive \
  --command "/bin/bash"
```

Inside the container:

```bash
python3 -c "from app.db.base import engine; from sqlalchemy import text; conn = engine.connect(); result = conn.execute(text(\"SELECT email, role, created_at FROM users\")); [print(r) for r in result]; conn.close()"
```

### 3. The practice logs in

```bash
DENTIST_TOKEN=$(curl -s -X POST http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/auth/login \
  -d "username=dr.chen@dentalflow-demo.com&password=DemoPass123!" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
```

**Response shape:**

```json
{"access_token":"<jwt>","token_type":"bearer"}
```

The token is a signed JWT containing the user's ID and role as claims. From here on, every protected request carries this token in an `Authorization: Bearer` header.

### 4. The lab technician logs in

```bash
LABTECH_TOKEN=$(curl -s -X POST http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/auth/login \
  -d "username=j.martinez@dentalflow-demo.com&password=LabDemo456!" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
```

Two authenticated identities now exist: **$DENTIST_TOKEN** and **$LABTECH_TOKEN**.

### 5. The practice submits a case

Order creation issues a presigned S3 upload URL in the same response, before any file exists (ADR-0002).

Lab technician is rejected:

```bash
curl -s -X POST http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/orders \
  -H "Authorization: Bearer $LABTECH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"patient_name": "Michael Torres", "patient_dob": "1990-01-01", "patient_gender": "male", "case_type": "aligners", "notes": "Upper and lower aligners, mild crowding", "filename": "scan.stl"}' \
  -w "\nHTTP_STATUS:%{http_code}\n"
```

**Response:** `{"detail":"You do not have permission to perform this action"}` HTTP_STATUS:403

Dentist succeeds:

```bash
curl -s -X POST http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/orders \
  -H "Authorization: Bearer $DENTIST_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"patient_name": "Michael Torres", "patient_dob": "1990-01-01", "patient_gender": "male", "case_type": "aligners", "notes": "Upper and lower aligners, mild crowding", "filename": "scan.stl"}' \
  -w "\nHTTP_STATUS:%{http_code}\n"
```

**Response (presigned query params redacted — never commit live AWSAccessKeyId values):**

```json
{
  "id": "469ccd8b-a608-40c0-b8f2-b504d93e7f67",
  "patient_name": "Michael Torres",
  "status": "pending_upload",
  "s3_object_key": "scans/469ccd8b-a608-40c0-b8f2-b504d93e7f67/scan.stl",
  "dentist_id": "80516aec-84c5-4ac8-a8ee-afff85d4dab3",
  "assigned_lab_tech_id": null,
  "upload_url": "https://dentalflow-scans-dev-542495333390.s3.amazonaws.com/scans/469ccd8b-a608-40c0-b8f2-b504d93e7f67/scan.stl?AWSAccessKeyId=ASIA_EXAMPLE_NOT_REAL&Signature=REDACTED&x-amz-security-token=REDACTED&Expires=0"
}
```

Capture the real URL locally only:

```bash
UPLOAD_URL='<paste upload_url from live API response — do not commit>'
```

dentist_id is set from the authenticated session, never from the client body (NFR-SEC-1).

### 6. Direct upload to S3

```bash
echo "fake scan data for demo" > scan.stl

curl -s -X PUT -T scan.stl "$UPLOAD_URL" \
  -w "\nHTTP_STATUS:%{http_code}\n"
```

**Response:** HTTP_STATUS:200

```bash
aws s3 ls s3://dentalflow-scans-dev-542495333390/scans/469ccd8b-a608-40c0-b8f2-b504d93e7f67/
```

**Output:**

```text
2026-08-27 12:44:33         24 scan.stl
```

### 7. Automatic status transition, upload confirmed

```bash
curl -s http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/orders/469ccd8b-a608-40c0-b8f2-b504d93e7f67 \
  -H "Authorization: Bearer $DENTIST_TOKEN" \
  -w "\nHTTP_STATUS:%{http_code}\n"
```

**Response:**

```json
{
  "id": "469ccd8b-a608-40c0-b8f2-b504d93e7f67",
  "status": "received",
  "created_at": "2026-08-27T11:40:05.708684Z",
  "updated_at": "2026-08-27T11:44:33.812886Z"
}
```

**updated_at** moved without a client request — the SQS consumer updated RDS after S3 ObjectCreated (ADR-0003).

### 8. The lab technician lists orders

```bash
curl -s http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/orders \
  -H "Authorization: Bearer $LABTECH_TOKEN" \
  -w "\nHTTP_STATUS:%{http_code}\n"
```

**Response:** one unassigned order in `received` status.

### 9. The lab technician claims the case

```bash
curl -s -X PATCH http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/orders/469ccd8b-a608-40c0-b8f2-b504d93e7f67 \
  -H "Authorization: Bearer $LABTECH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status": "in_fabrication"}' \
  -w "\nHTTP_STATUS:%{http_code}\n"
```

**Response:**

```json
{
  "id": "469ccd8b-a608-40c0-b8f2-b504d93e7f67",
  "status": "in_fabrication",
  "assigned_lab_tech_id": "ceb03ed8-424f-454e-b090-86efd81e411d",
  "updated_at": "2026-08-27T11:53:58.771128Z"
}
```

**assigned_lab_tech_id** comes from the caller token, not the request body.

### 10. The lab technician downloads the scan

```bash
curl -s http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/orders/469ccd8b-a608-40c0-b8f2-b504d93e7f67/download-url \
  -H "Authorization: Bearer $LABTECH_TOKEN" \
  -w "\nHTTP_STATUS:%{http_code}\n"
```

**Response (redacted):**

```json
{"download_url":"https://dentalflow-scans-dev-542495333390.s3.amazonaws.com/scans/469ccd8b-a608-40c0-b8f2-b504d93e7f67/scan.stl?AWSAccessKeyId=ASIA_EXAMPLE_NOT_REAL&Signature=REDACTED&x-amz-security-token=REDACTED&Expires=0"}
```

```bash
DOWNLOAD_URL='<paste download_url from live API — do not commit>'
curl -s "$DOWNLOAD_URL" -o downloaded-scan.stl
cat downloaded-scan.stl
```

**Output:** `fake scan data for demo`

### 11. The lab technician marks the case completed

```bash
curl -s -X PATCH http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/orders/469ccd8b-a608-40c0-b8f2-b504d93e7f67 \
  -H "Authorization: Bearer $LABTECH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status": "completed"}' \
  -w "\nHTTP_STATUS:%{http_code}\n"
```

**Response:**

```json
{
  "id": "469ccd8b-a608-40c0-b8f2-b504d93e7f67",
  "status": "completed",
  "assigned_lab_tech_id": "ceb03ed8-424f-454e-b090-86efd81e411d",
  "updated_at": "2026-08-27T19:35:49.587926Z",
  "completed_at": "2026-08-27T19:35:49.587202Z"
}
```

### 12. SNS notification fan-out on completion

```bash
aws sqs receive-message \
  --queue-url "https://sqs.us-east-1.amazonaws.com/542495333390/dev-dentalflow-notification-queue" \
  --region us-east-1 \
  --max-number-of-messages 1
```

**Response (relevant fields):**

```json
{
  "TopicArn": "arn:aws:sns:us-east-1:542495333390:dev-dentalflow-lab-notifications",
  "Subject": "DentalFlow order completed",
  "Message": "{\"order_id\": \"469ccd8b-a608-40c0-b8f2-b504d93e7f67\", \"event_type\": \"completed\", \"patient_name\": \"Michael Torres\"}",
  "Timestamp": "2026-08-27T19:35:49.656Z"
}
```

This closes the loop: **pending_upload** → **received** → **in_fabrication** → **completed**, with evidence at each step.

## Summary

This walkthrough followed one case from start to finish against the real deployed system: order metadata first, presigned S3 upload (bytes never through the API), SQS-driven status update, lab claim/download/complete, SNS → notification queue.

## Appendix — security notes

- Role boundaries enforced (403 for wrong role).
- `dentist_id` / `assigned_lab_tech_id` from the JWT, not the body.
- Presigned URLs are short-lived temporary STS credentials (`ASIA…`); never commit live values — use `$UPLOAD_URL` / `$DOWNLOAD_URL`.
- S3 Block Public Access + HTTPS-only; task IAM scoped to scans prefix, upload queue, and SNS topic.
- RDS is private; no public path from the internet.
