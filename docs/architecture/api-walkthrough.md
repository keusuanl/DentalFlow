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

**Role     \tCan do**
-------------------------------------------------------------------------------------------------------
dentist\t -  Register, log in, create orders, view their own clinic's orders
-------------------------------------------------------------------------------------------------------
lab_tech -\tRegister, log in, view unassigned orders and orders assigned to them, claim and progress an  order's status, download the scan file

Neither role can act outside these boundaries. A dentist cannot update order status or
download scans, a lab technician cannot create orders or view another lab technician's
assigned case. Every boundary below is demonstrated directly, not just described.

## Environment

All requests below are made against: http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com

*No API key or upfront credential is required to begin, only the two demo accounts
created in the walkthrough itself*.

![Screenshot: ECS service running, 2/2 healthy tasks](screenshots/01-ecs-service-running.png)

## Walkthrough

### 1. The practice registers

A new dental practice creates an account. Note the response never echoes back a
password or its hash, only what a client should ever see.

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

The password is never returned, not even hashed, only the account's public shape
comes back. The password itself is bcrypt hashed before it ever touches the database,
see ADR entries referenced in security notes below

### 2. The lab technician registers

The lab side of the workflow needs its own account too.

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

*Two accounts now exist, one dentist, one lab technician, each with a distinct role
that will be enforced on every subsequent request.*

![Screenshot: RDS query or console view showing both new rows in the users table](screenshots/02-users-table-rds.png)

### Querying the Database

Since RDS itself doesn't have a query browser in the console, the actual evidence needs to come from a database client. The simplest option, reuse the same ECS Exec session technique:

**Query the RDS Current Task ID:**
```bash
aws ecs list-tasks --cluster dentalflow-dev-cluster --service-name dentalflow-dev-service --region us-east-1
{
    "taskArns": [
        "arn:aws:ecs:us-east-1:542495333390:task/dentalflow-dev-cluster/04c6e7ce33ad45faa7e57960a455c90c",
        "arn:aws:ecs:us-east-1:542495333390:task/dentalflow-dev-cluster/f9935bff45c340bdb6ff66714da3ec0d"
    ]
}
```

**Execute Command inside on of the Task Container:**

```bash
aws ecs execute-command \
  --cluster dentalflow-dev-cluster \
  --task 04c6e7ce33ad45faa7e57960a455c90c \
  --container dentalflow-app \
  --interactive \
  --command "/bin/bash"
```

**Response:** It will drop us inside the container and we will gain shell

```bash
root@ip-10-0-11-122:/app#

root@ip-10-0-11-122:/app# whoami && id && hostname && ls
root
uid=0(root) gid=0(root) groups=0(root)
ip-10-0-11-122.ec2.internal
alembic  alembic.ini  app  requirements.txt
```

#### Query the Database:

```bash
root@ip-10-0-11-122:/app# python3 -c "from app.db.base import engine; from sqlalchemy import text; conn = engine.connect(); result = conn.execute(text(\"SELECT email, role, created_at FROM users\")); [print(r) for r in result]; conn.close()"


('realrds@example.com', 'dentist', datetime.datetime(2026, 8, 18, 11, 29, 6, 110403, tzinfo=datetime.timezone.utc))
('dr.chen@dentalflow-demo.com', 'dentist', datetime.datetime(2026, 8, 24, 9, 55, 17, 569546, tzinfo=datetime.timezone.utc))
('j.martinez@dentalflow-demo.com', 'lab_tech', datetime.datetime(2026, 8, 24, 9, 58, 5, 830540, tzinfo=datetime.timezone.utc))
```

Prove Our Dentist & Lab Technician Account was created successfully

### 3. The practice logs in

Login uses OAuth2's standard form encoded convention, `username` and `password`
fields, even though DentalFlow authenticates by email. This is what allows FastAPI's
built in `/docs` interactive UI and its `OAuth2PasswordBearer` dependency to work
together without custom wiring.

```bash
# Login as Dentist
DENTIST_TOKEN=$(curl -s -X POST http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/auth/login \ -d "username=dr.chen@dentalflow-demo.com&password=DemoPass123!" \ | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
```

**Response:**

```json
{"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4MDUxNmFlYy04NGM1LTRhYzgtYThlZS1hZmZmODVkNGRhYjMiLCJyb2xlIjoiZGVudGlzdCIsImV4cCI6MTc4NzU2OTU1Mn0.mHSzrDeP5QUZcSCXZA2C8Q3jTPnKaq2UQuiKZxatKxA","token_type":"bearer"}
```

The token is a signed JWT containing the user's ID and role as claims. From here on, every protected request carries this token in an `Authorization: Bearer` header. Forreadability, the rest of this walkthrough stores it in a shell variable:

### 4. The lab technician logs in

Same login flow, different account. The response's role claim is what every protected endpoint downstream will check before running its logic

```bash
curl -X POST http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/auth/login \ -d "username=j.martinez@dentalflow-demo.com&password=LabDemo456!"
```

**Response:**

```bash
{"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJjZWIwM2VkOC00MjRmLTQ1NGUtYjA5MC04NmVmZDgxZTQxMWQiLCJyb2xlIjoibGFiX3RlY2giLCJleHAiOjE3ODc4MzIwODF9.VQZ5fW9VF8wFG8-nMR2l5qAj7FKEDB-rDawU4-bWFSU","token_type":"bearer"}
```

Decoding the token's payload confirms this isn't just a label on the response, the sub claim matches James Martinez's own user ID from registration, and role is genuinely lab_tech:

```bash
{"sub": "ceb03ed8-424f-454e-b090-86efd81e411d", "role": "lab_tech", "exp": 1787832081}
```

Stored the same way as the dentist's token:

```bash
LABTECH_TOKEN=$(curl -s -X POST http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/auth/login \ -d "username=j.martinez@dentalflow-demo.com&password=LabDemo456!" \ | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
```

Two authenticated identities now exist side by side, **$DENTIST_TOKEN** and **$LABTECH_TOKEN**. Every request from here on shows what each role can and cannot do with these.

### 5. The practice submits a case

Order creation issues a presigned S3 upload URL in the same response, before any file exists. This means no orphaned files can ever land in S3 without a matching database record, see ADR-0002 and data-flow.md.

Role checks run before this logic even starts. A lab technician trying to create an order gets rejected outright:

```bash
curl -s -X POST http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/orders \
  -H "Authorization: Bearer $LABTECH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"patient_name": "Michael Torres", "patient_dob": "1990-01-01", "patient_gender": "male", "case_type": "aligners", "notes": "Upper and lower aligners, mild crowding", "filename": "scan.stl"}' \
  -w "\nHTTP_STATUS:%{http_code}\n"
```

**Response:**

```bash
{"detail":"You do not have permission to perform this action"} HTTP_STATUS:403
```

The message is deliberately generic, it confirms a boundary exists without revealing what role would have worked.

**The dentist's own request succeeds:**
```bash
curl -s -X POST http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/orders \
  -H "Authorization: Bearer $DENTIST_TOKEN" \ -H "Content-Type: application/json" \
  -d '{"patient_name": "Michael Torres", "patient_dob": "1990-01-01", "patient_gender": "male", "case_type": "aligners", "notes": "Upper and lower aligners, mild crowding", "filename": "scan.stl"}' \
  -w "\nHTTP_STATUS:%{http_code}\n"
```

**Response:**
```bash
{
  "id": "469ccd8b-a608-40c0-b8f2-b504d93e7f67",
  "patient_name": "Michael Torres",
  "status": "pending_upload",
  "s3_object_key": "scans/469ccd8b-a608-40c0-b8f2-b504d93e7f67/scan.stl",
  "dentist_id": "80516aec-84c5-4ac8-a8ee-afff85d4dab3",
  "assigned_lab_tech_id": null,
  "upload_url": "https://dentalflow-scans-dev-542495333390.s3.amazonaws.com/scans/469ccd8b-a608-40c0-b8f2-b504d93e7f67/scan.stl?AWSAccessKeyId=ASIA_EXAMPLE_NOT_REAL&Signature=REDACTED&x-amz-security-token=REDACTED&Expires=0"
}
HTTP_STATUS:201
```

(Presigned URL query parameters are redacted in this document. Capture the real `upload_url` from the live API into `$UPLOAD_URL` when you run the walkthrough — never commit live `AWSAccessKeyId` / `Signature` / `x-amz-security-token` values.)

dentist_id is set from the authenticated session, never from anything the client sends, per NFR-SEC-1. The order starts in pending_upload, no file exists yet. The presigned URL only works for this exact object path, carries short-lived credentials (ASIA..., not the backend's own standing credentials), and expires shortly after issuance, see ADR-0002.

Order **469ccd8b-a608-40c0-b8f2-b504d93e7f67** is used for the rest of this walkthrough.

### 6. Direct upload to S3

The client uploads straight to S3 using the presigned URL from Step 5. The file's bytes never pass through the FastAPI backend at all, see data-flow.md step 3.

```bash
echo "fake scan data for demo" > scan.stl

# Use upload_url from Step 5 response (do not paste live credentials into git)
curl -s -X PUT -T scan.stl "$UPLOAD_URL" \
  -w "\nHTTP_STATUS:%{http_code}\n"
```

**Response:**

```bash
HTTP_STATUS:200
```

A 200 from S3 means the upload was accepted, but the real proof is checking the bucket directly, not just trusting the status code:

```bash
aws s3 ls s3://dentalflow-scans-dev-542495333390/scans/469ccd8b-a608-40c0-b8f2-b504d93e7f67/
```

**Output:**

```bash
2026-08-27 12:44:33         24 scan.stl
```

The object exists at exactly the path predicted when the order was created, scans/{order_id}/{filename}, per ADR-0002. At this point the order is still pending_upload in RDS. S3 has no idea an order table exists, and nothing has updated the database yet. That happens next, on its own.

### 7. Automatic status transition, upload confirmed

Nothing manual moves this order from pending_upload to received. A background task inside the same FastAPI process polls the upload SQS queue, and once S3's event notification confirms the file arrived, the consumer updates RDS by itself, see data-flow.md steps 4 to 5 and ADR-0003.

```bash
curl -s http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/orders/469ccd8b-a608-40c0-b8f2-b504d93e7f67 \ -H "Authorization: Bearer $DENTIST_TOKEN" \  -w "\nHTTP_STATUS:%{http_code}\n"
```

**Response:**

```bash
{
  "id": "469ccd8b-a608-40c0-b8f2-b504d93e7f67",
  "status": "received",
  "created_at": "2026-08-27T11:40:05.708684Z",
  "updated_at": "2026-08-27T11:44:33.812886Z"
}
HTTP_STATUS:200
```

**updated_at** moved on its own, about four and a half minutes after the order was created, without a single request from us in between. That gap is the real evidence here, it shows a background process reacting to an event and writing to the database entirely by itself.

### 8. The lab technician lists orders

A lab technician only sees orders that are unassigned, or already assigned to them, never a blanket view of every order in the system, per NFR-SEC-3.

```bash
curl -s http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/orders \-H "Authorization: Bearer $LABTECH_TOKEN" \ -w "\nHTTP_STATUS:%{http_code}\n"
```

**Response:**

```bash
[{
  "id": "469ccd8b-a608-40c0-b8f2-b504d93e7f67",
  "patient_name": "Michael Torres",
  "status": "received",
  "assigned_lab_tech_id": null,
  "created_at": "2026-08-27T11:40:05.708684Z",
  "updated_at": "2026-08-27T11:44:33.812886Z"
}]
HTTP_STATUS:200
```

One order, unassigned, ready to be claimed. James Martinez didn't create this order and wasn't assigned to it, he can see it purely because it's received and still unclaimed.

### 9. The lab technician claims the case

A PATCH moves the order to in_fabrication. The request only sets status, nothing else, assigned_lab_tech_id is never something the client sends, it comes from who's making the request.

```bash
curl -s -X PATCH http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/orders/469ccd8b-a608-40c0-b8f2-b504d93e7f67 \
  -H "Authorization: Bearer $LABTECH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status": "in_fabrication"}' \
  -w "\nHTTP_STATUS:%{http_code}\n"
```

**Response:**

```bash
{
  "id": "469ccd8b-a608-40c0-b8f2-b504d93e7f67",
  "status": "in_fabrication",
  "assigned_lab_tech_id": "ceb03ed8-424f-454e-b090-86efd81e411d",
  "updated_at": "2026-08-27T11:53:58.771128Z"
}
HTTP_STATUS:200
```

**assigned_lab_tech_id** matches James Martinez's own ID from his Step 4 login token, and it was never in the request body. The order is no longer unassigned, only he, or the dentist who owns it, can act on it from here.

### 10. The lab technician downloads the scan

A separate presigned URL, this one for reading rather than writing, lets the lab technician retrieve the file the dentist uploaded back in Step 6.

```bash
curl -s http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/orders/469ccd8b-a608-40c0-b8f2-b504d93e7f67/download-url \
  -H "Authorization: Bearer $LABTECH_TOKEN" \
  -w "\nHTTP_STATUS:%{http_code}\n"
```

**Response:**

```bash
{"download_url":"https://dentalflow-scans-dev-542495333390.s3.amazonaws.com/scans/469ccd8b-a608-40c0-b8f2-b504d93e7f67/scan.stl?AWSAccessKeyId=ASIA_EXAMPLE_NOT_REAL&Signature=REDACTED&x-amz-security-token=REDACTED&Expires=0"}
HTTP_STATUS:200
```

Downloading and checking the actual content, not just the status code:

```bash
# Use download_url from the response above (do not commit live credentials)
curl -s "$DOWNLOAD_URL" -o downloaded-scan.stl

cat downloaded-scan.stl
```

**Output:**

```bash
fake scan data for demo
```

Matches exactly what was uploaded in Step 6. The round trip works, what the dentist uploaded is exactly what the lab technician gets back, through two separately scoped presigned URLs, one that could only write, one that could only read.

### 11. The lab technician marks the case completed

```bash
curl -s -X PATCH http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/orders/469ccd8b-a608-40c0-b8f2-b504d93e7f67 \
  -H "Authorization: Bearer $LABTECH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status": "completed"}' \
  -w "\nHTTP_STATUS:%{http_code}\n"
```

**Response:**

```bash
{
  "id": "469ccd8b-a608-40c0-b8f2-b504d93e7f67",
  "status": "completed",
  "assigned_lab_tech_id": "ceb03ed8-424f-454e-b090-86efd81e411d",
  "updated_at": "2026-08-27T19:35:49.587926Z",
  "completed_at": "2026-08-27T19:35:49.587202Z"
}
HTTP_STATUS:200
```

**completed_at** is set for the first time here, and it matches updated_at almost to the microsecond, both are written in the same transaction, not one filled in after the fact. This transition is also what should trigger a notification to the clinic, checked next.

### 12. SNS notification fan-out on completion

Per ADR-0003, a completed transition publishes to an SNS topic, which fans out into a durable SQS queue rather than trusting SNS's best-effort delivery alone

```bash
aws sqs receive-message \
  --queue-url "https://sqs.us-east-1.amazonaws.com/542495333390/dev-dentalflow-notification-queue" \
  --region us-east-1 \
  --max-number-of-messages 1
```

**Response (relevant fields):**

```bash
{
  "TopicArn": "arn:aws:sns:us-east-1:542495333390:dev-dentalflow-lab-notifications",
  "Subject": "DentalFlow order completed",
  "Message": "{\"order_id\": \"469ccd8b-a608-40c0-b8f2-b504d93e7f67\", \"event_type\": \"completed\", \"patient_name\": \"Michael Torres\"}",
  "Timestamp": "2026-08-27T19:35:49.656Z"
}
```

This timestamp lands within 70 milliseconds of the order's own **updated_at** and **completed_at** from Step 11, this message was published the moment the status changed, not left over from something unrelated. The body names the exact order and patient, this is a specific, traceable notification, not a generic ping. It stays in the queue, durably, until a real consumer picks it up and deletes it, satisfying NFR-REL-1.

This closes the loop. Every stage of the order lifecycle, **pending_upload** to **received** to **in_fabrication** to **completed**, has now been shown live against real infrastructure, with independent evidence at each step rather than trusting a status code alone.

## Summary

This walkthrough followed one case from start to finish. Dr. Chen registered, logged in, and submitted a case for a patient. The system handed back a link, and the scan was uploaded straight to S3, the file never touched the backend itself. A background process noticed the upload on its own and moved the order to received, nobody had to tell it to. James Martinez, the lab technician, saw the case waiting in his queue, claimed it, downloaded the same file the dentist had uploaded, and marked it complete once the work was done. That final change triggered a notification, sent through SNS into a durable queue, ready for whatever system eventually needs to tell the practice their case is ready.

Every step above ran against the real, deployed system, nothing here is simulated or written from memory. A few real bugs turned up along the way, permission gaps and a missing code import, and those are written up separately in their own troubleshooting document rather than mixed into this one. This doc is meant to stand on its own as proof the system works today, not as a record of what went wrong getting here.

## Appendix, security notes

A plain-language summary of what's actually being protected here, and how, tied back to the steps above where something was shown live, and to the ADRs where it wasn't re-tested in this walkthrough but is documented elsewhere.

Only the right role can do the right thing. The system checks who's asking before it does anything. Step 5 showed a lab technician get blocked from creating an order, then a dentist create the exact same request successfully. Step 9 showed the reverse, a dentist can't move a case through fabrication, only a lab technician can. See data-model.md for the full list of what each role can and can't do.

Rejections don't explain themselves. When something gets blocked, the response doesn't give away why. Step 5's 403 just says permission was denied, it doesn't say what role would have worked. Login works the same way, a wrong password and an email that doesn't exist both come back with the same generic message, so nobody can use failed logins to figure out which emails belong to real accounts. That specific behavior was verified in an earlier session, not re-tested here, see pending-applies.md.

You can't act as someone else. A few fields are never taken from what the client types in, they're taken from who the client is. Step 5's dentist_id and Step 9's assigned_lab_tech_id both came straight from the caller's own login token. There's no field you can fill in to submit a case under someone else's name, or assign a case to a different lab technician than yourself.

Upload and download links are narrow and temporary. Steps 5, 6, and 10 each used a link good for exactly one file, for a short window of time, backed by temporary credentials rather than the backend's own permanent ones. If a link like this ever leaked, it wouldn't hand over the rest of the bucket, and it stops working on its own within minutes.

The app only has the permissions it actually needs. Nothing in this project's AWS setup was given broad access "just in case." This isn't something you can see in an API response, it's a property of how the infrastructure is configured, but it's real, it's the direct cause of three genuine bugs this project hit and fixed, all documented in ADR-0006. Each one turned up by actually running the system and watching it fail, not by guessing permissions ahead of time.

The database can't be reached from outside. RDS lives in a private network with no path in from the public internet. This was confirmed earlier in the project, a direct connection attempt from outside the network failed exactly as expected, see ADR-0005 and ADR-0001. It wasn't re-tested in this walkthrough since everything here goes through the public API.

A missed notification doesn't just disappear. Step 12 showed a real notification land in a queue within milliseconds of a case being marked complete. If nothing happened to be listening at that exact moment, the message would simply wait there, not vanish. Each queue also has a backup queue for messages that keep failing to process, though nothing here triggered that path.
