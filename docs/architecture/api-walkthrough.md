# DentalFlow, API Walkthrough

## Introduction

This document is the primary technical proof of DentalFlow, a working demonstration of
every flow the system supports, run against the real, deployed environment, real ECS
Fargate tasks, real RDS, real S3, real SQS, real SNS. There is no frontend, see
ADR-0009, DentalFlow is demonstrated and consumed directly through its API.

Every request below is real, run against the live ALB URL, with real responses
included as shown, not fabricated or idealized. Where a step has a corresponding piece
of AWS console evidence, a screenshot placeholder marks exactly what to capture.

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

| Role | Can do |
|---|---|
| dentist | Register, log in, create orders, view their own clinic's orders |
| lab_tech | Register, log in, view unassigned orders and orders assigned to them, claim and progress an order's status, download the scan file |

Neither role can act outside these boundaries. A dentist cannot update order status or
download scans, a lab technician cannot create orders or view another lab technician's
assigned case. Every boundary below is demonstrated directly, not just described.

## Environment

All requests below are made against:
http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com

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

Two accounts now exist, one dentist, one lab technician, each with a distinct role
that will be enforced on every subsequent request.

![Screenshot: RDS query or console view showing both new rows in the users table](screenshots/02-users-table-rds.png)

### Querying the Database:

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
**Response:**
It will drop us inside the container and we will gain shell
```bash
root@ip-10-0-11-122:/app#

root@ip-10-0-11-122:/app# whoami && id && hostname && ls
root
uid=0(root) gid=0(root) groups=0(root)
ip-10-0-11-122.ec2.internal
alembic  alembic.ini  app  requirements.txt
```

**Query the Database**
```bash
root@ip-10-0-11-122:/app# python3 -c "from app.db.base import engine; from sqlalchemy import text; conn = engine.connect(); result = conn.execute(text(\"SELECT email, role, created_at FROM users\")); [print(r) for r in result]; conn.close()"


('realrds@example.com', 'dentist', datetime.datetime(2026, 8, 18, 11, 29, 6, 110403, tzinfo=datetime.timezone.utc))
('dr.chen@dentalflow-demo.com', 'dentist', datetime.datetime(2026, 8, 24, 9, 55, 17, 569546, tzinfo=datetime.timezone.utc))
('j.martinez@dentalflow-demo.com', 'lab_tech', datetime.datetime(2026, 8, 24, 9, 58, 5, 830540, tzinfo=datetime.timezone.utc))
```
*Our Dentist & Lab Technician Account was created successfully*

### 3. The practice logs in

Login uses OAuth2's standard form encoded convention, `username` and `password`
fields, even though DentalFlow authenticates by email. This is what allows FastAPI's
built in `/docs` interactive UI and its `OAuth2PasswordBearer` dependency to work
together without custom wiring.

```bash
curl -X POST http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/auth/login \
  -d "username=dr.chen@dentalflow-demo.com&password=DemoPass123!"
```

**Response:**
```json
{"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4MDUxNmFlYy04NGM1LTRhYzgtYThlZS1hZmZmODVkNGRhYjMiLCJyb2xlIjoiZGVudGlzdCIsImV4cCI6MTc4NzU2OTU1Mn0.mHSzrDeP5QUZcSCXZA2C8Q3jTPnKaq2UQuiKZxatKxA","token_type":"bearer"}
```
The token is a signed JWT containing the user's ID and role as claims. From here on, every protected request carries this token in an `Authorization: Bearer` header. Forreadability, the rest of this walkthrough stores it in a shell variable:

```bash
DENTIST_TOKEN=$(curl -s -X POST http://dentalflow-dev-alb-647309105.us-east-1.elb.amazonaws.com/auth/login \
  -d "username=dr.chen@dentalflow-demo.com&password=DemoPass123!" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
```