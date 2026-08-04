# ADR-005: RDS PostgreSQL for Application Data

## Status
Accepted

## Context
DentalFlow requires a relational database for order and patient-record metadata,
including status transitions across the fabrication workflow. Per NFR-REL-2 and
NFR-REL-3, the application must tolerate the loss of a single compute instance without
full service outage. Unlike the NAT Gateway (ADR-001), where losing the resource's AZ
only affects outbound-only capability while inbound traffic to running tasks continues
unaffected, losing the AZ hosting the database means the entire application loses its
data layer. This is a full outage, not a degraded, recoverable state. Per NFR-SEC-1,
NFR-SEC-4, and NFR-DATA-1, the database must not be publicly accessible and must use
realistic, non-theatrical security controls. Per NFR-SEC-5, credentials must never
appear in code or committed configuration.

## Decision

Multi-AZ deployment is enabled. This is a deliberate departure from ADR-001's
single-NAT-Gateway cost tradeoff, on the principle of calibrated consistency rather
than blind consistency: redundancy decisions should scale to the actual severity of
failure, not be applied uniformly regardless of blast radius. The database is the one
component where an AZ failure means full application outage, not degraded
functionality, so the same cost-saving logic applied to the NAT Gateway does not
transfer here. The cost impact is also negligible in practice, given this project's
established pattern of applying infrastructure for short, deliberate test windows and
destroying it promptly rather than leaving it running continuously, and the
implementation cost is a single configuration flag, not additional resources.

Instance class: db.t4g.micro, the smallest, free-tier-eligible option, following the
same start small, scale on evidence pattern used for ECS Fargate's task sizing in
ADR-004. Will be resized only if a real performance need is observed.

Public accessibility: disabled. The instance sits in the private subnets established
in ADR-001, publicly_accessible = false, with a security group restricting inbound
traffic to only the application's own security group, consistent with how S3
(ADR-002) and ECS tasks (ADR-004) are similarly isolated from direct internet
exposure.

Encryption at rest: the default AWS-managed KMS key, not a customer-managed key.
Encryption at rest genuinely uses KMS in both cases; the distinction is who owns and
controls the key, not whether KMS is involved at all. The AWS-managed key carries no
additional cost, while a customer-managed key incurs a monthly fee plus per-request
charges for capabilities (independent rotation policy, custom access auditing) that
are not required under NFR-DATA-1's PHI-lite scope. This is consistent with ADR-002's
SSE-S3 decision for the same reasoning.

Backup retention period: planned at 7 days, but changed to 1 day (RDS's minimum)
after a real apply attempt failed with a FreeTierRestrictionError. This account's
Free Plan tier doesn't allow 7 days. Found this by actually running it, not by
reading docs first.

Credentials: generated via Terraform's random_password resource and stored in AWS
Secrets Manager, never hardcoded or typed manually. The application will retrieve the
credential at runtime using its existing IAM task role (established in ADR-004), not
via environment variables. The generated password will still appear in Terraform's
state file in plain text; this reinforces why .tfstate must never be committed to
version control (already excluded via .gitignore) and is noted as a candidate for a
future decision around remote, encrypted state storage.

## Consequences

Positive: The database can survive the loss of a single AZ without full application
outage, directly satisfying NFR-REL-2 for the component with the highest failure
severity in the system. Credentials are never exposed in code, satisfying NFR-SEC-5.
The instance is fully isolated from direct internet access, satisfying NFR-SEC-1 and
NFR-SEC-4.

Negative (accepted tradeoff): Multi-AZ roughly doubles the instance's hourly cost
compared to a single instance. This is accepted given the severity-calibrated
reasoning above and this project's short-lived apply-and-destroy usage pattern. If
that usage pattern changes, for example, if dev infrastructure begins running
continuously for extended periods, this decision should be revisited, since the cost
calculus would shift meaningfully. The Terraform state file becomes a sensitive
artifact by necessity of generating credentials this way, requiring ongoing discipline
to keep it out of version control. -  1 day of backup retention is shorter than a real production setup would use(usually 7-35 days). This is a free-tier limit we're accepting for now. Should be
increased once this moves to a real paid account or CloudDent.

## Alternatives Considered

Single-AZ deployment, to remain cost-consistent with ADR-001's shared NAT Gateway
decision. Rejected: the blast radius of losing the database differs fundamentally from
losing outbound-only NAT capability. Applying the same redundancy tradeoff here would
be blind consistency rather than genuinely calibrated risk assessment.

Customer-managed KMS key, for full control over key rotation and access auditing.
Rejected for the same reasoning as ADR-002: the additional cost and operational
overhead is not justified under this project's PHI-lite scope, and remains the natural
upgrade path for a real production healthcare deployment or CloudDent at scale.
