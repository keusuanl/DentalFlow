# DentalFlow — Non-Functional Requirements

Every architecture and technology decision (see docs/adrs/) must be traceable to one or
more requirements below. If a decision doesn't satisfy any NFR here, that's a signal
either the decision needs reconsidering, or this document is missing something.

## 1. Security

- **NFR-SEC-1:** Authentication is enforced on every route or API that touches clinic or
  patient data. No unauthenticated access to clinic/patient data is permitted.
- **NFR-SEC-2:** Dentists (clinic role) may create and view scan/order records for their
  own clinic's patients, but may not modify lab-side processing data or order status.
  Lab technicians may update order/processing status but may not alter original patient
  PII/PHI submitted by the clinic.
- **NFR-SEC-3:** Lab technicians have read/write access only to orders assigned to them —
  not blanket access to all orders in the system.
- **NFR-SEC-4:** IAM policies are scoped to the minimum actions and resources each
  service or role requires to perform its function. No wildcard (`*`) actions or
  resources are permitted.
- **NFR-SEC-5:** Secrets (database credentials, API keys, etc.) are stored in AWS
  Secrets Manager or SSM Parameter Store. Secrets must never appear in application code,
  Dockerfiles, or environment variables checked into version control.
- **NFR-SEC-6:** Service-to-service calls (e.g. backend → S3, backend → SQS/SNS) are
  authenticated via IAM roles, not static credentials.

## 2. Reliability

- **NFR-REL-1:** A failed or dropped lab notification is a critical failure, not a minor
  bug — a practice never learning their patient's order stalled breaks trust across
  patient, practice, and lab. Notification delivery must be durable: if the initial
  delivery attempt fails, the message must be retried and persisted until a consumer
  successfully processes it (this is why SQS is used as a durable buffer rather than
  relying on SNS's best-effort delivery alone — see ADR-002).
- **NFR-REL-2:** The web application must tolerate the loss of a single compute instance
  without full service outage — achieved via auto-scaling and self-healing (ECS Fargate
  service with a minimum healthy task count, replaced automatically on failure).
- **NFR-REL-3:** The system must recover automatically from the loss of a single compute
  instance without manual intervention, within a time bound to be defined in the ADR
  covering ECS service configuration (target healthy task count, health check settings).

## 3. Observability

- **NFR-OBS-1:** Key activity across the workflow (authentication, upload, order status
  change, notification sent/received) must be tracked and auditable — it must be
  possible to reconstruct what happened to a given order and when.
- **NFR-OBS-2:** System downtime or service degradation must be detected automatically
  and trigger alerting fast enough to enable rapid incident response, not be discovered
  after the fact via a support complaint.
- **NFR-OBS-3:** Downtime or degraded service must trigger an alert within a bounded,
  defined time window rather than being discovered manually. Specific metrics monitored
  and alert thresholds are defined in the ADR covering CloudWatch/observability design.

## 4. Performance

- **NFR-PERF-1:** Scan upload and lab notification delivery must complete within a
  bounded, predictable time for typical file sizes — slow or unpredictable delivery
  undermines practice and patient trust in the same way a dropped notification does
  (see NFR-REL-1). Specific latency targets are defined in the ADR covering the
  upload/notification pipeline.

## 5. Cost

- **NFR-COST-1:** Infrastructure choices should remain free-tier friendly wherever
  reasonable, given this is a learning/portfolio project, not a funded production system.

## 6. Data Sensitivity (PHI-lite)

- **NFR-DATA-1:** Patient scan data and PII are treated with realistic (not theatrical)
  security controls — private storage, encryption at rest and in transit, least-privilege
  access — but this project does not implement full regulatory compliance (e.g. no
  customer-managed KMS key rotation policy, no full audit-to-SIEM pipeline). This is a
  deliberate scoping decision, not an oversight (see ADR-000).
