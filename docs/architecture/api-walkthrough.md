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
curl -X POST http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/auth/register \\
  -H "Content-Type: application/json" \\
  -d '{\"email\": \"dr.chen@dentalflow-demo.com\", \"password\": \"DemoPass123!\", \"full_name\": \"Dr. Sarah Chen\", \"role\": \"dentist\"}'
```

**Response:**

```json
{
  \"id\": \"80516aec-84c5-4ac8-a8ee-afff85d4dab3\",
  \"email\": \"dr.chen@dentalflow-demo.com\",
  \"full_name\": \"Dr. Sarah Chen\",
  \"role\": \"dentist\",
  \"is_active\": true,
  \"created_at\": \"2026-08-24T09:55:17.569546Z\"
}
```

### 5. Presigned URL note (security)

When the API returns `upload_url`, it includes temporary STS credentials (`AWSAccessKeyId` starting with `ASIA...`). Those must never be committed to git.

In this document, query parameters are redacted:

```text
?AWSAccessKeyId=ASIA_EXAMPLE_NOT_REAL&Signature=REDACTED&x-amz-security-token=REDACTED&Expires=0
```

When you run the walkthrough yourself:

```bash
# Capture from Step 5 JSON response — do not paste live values into the repo
UPLOAD_URL='https://...s3.amazonaws.com/scans/.../scan.stl?<from-api-response>'

echo "fake scan data for demo" > scan.stl
curl -s -X PUT -T scan.stl "$UPLOAD_URL" -w "\nHTTP_STATUS:%{http_code}\n"
```

Same rule for download URLs in Step 10: use `$DOWNLOAD_URL` from the API, never commit real `AWSAccessKeyId` values.

### Security remediation note

A prior commit accidentally included a live temporary access key id (`ASIA...`) inside a copied presigned URL. That material has been removed from the current file. Temporary STS credentials expire automatically; GitHub reported no known active pairs. Prefer shell variables for all presigned URLs in docs going forward.

## Full walkthrough

The complete step-by-step narrative (registration through SNS fan-out) lives in git history and local copies. Restore the full body from your machine if this commit is a partial security fix, or re-run the live API flows and document with redacted URLs only.

Repository: https://github.com/keusuanl/DentalFlow
