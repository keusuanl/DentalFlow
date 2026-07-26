# ADR-000: Single-Tenant Scope for DentalFlow (MVP)

## Status
Accepted

## Context
DentalFlow is the first hands-on build in a longer path toward CloudDent, a multi-tenant SaaS platform for dental practices. This project is informed by real-world experience at a digital dental company providing device-to-lab digital workflows (intraoral scanners, scan upload, lab fabrication, and delivery back to the practice) at scale across many practices. I have not previously built a SaaS system end-to-end. Multi-tenancy adds cross-cutting complexity — tenant isolation in the data model, IAM scoping, and networking — that would compound with the complexity of learning AWS, Terraform, and production architecture patterns for the first time.

## Decision
DentalFlow will be built as a single-tenant system, modeling the laboratory as an internal team rather than an isolated tenant boundary, deliberately deferring multi-tenant architecture to a future project (CloudDent). This scope is chosen to build deep, hands-on fundamentals — Terraform/IaC, DevOps workflow, troubleshooting, and observability — before taking on the added complexity of multi-tenancy.

## Consequences

**Positive:** Deferring multi-tenancy means the data model, IAM policies, and network boundaries don't need to account for cross-tenant isolation, letting focus stay on deeply understanding Terraform-driven infrastructure, DevOps workflow, and intentionally practicing troubleshooting and observability.

**Negative:** Infrastructure built here will require rework for CloudDent — most notably the S3 bucket/object layout, which will need per-tenant prefixing or partitioning that isn't necessary for a single practice. This project also won't provide hands-on experience with tenant-isolation-specific concerns such as PostgreSQL row-level security (RLS) or multi-tenant table design, deeper S3 access-boundary patterns, or multi-account/multi-tenant environment separation — those remain open learning areas for the CloudDent phase.

## Alternatives Considered
**Build CloudDent multi-tenant from the start.** Rejected in favor of solving a single, well-scoped business problem first. Building single-tenant creates a safer environment to intentionally break things, troubleshoot, and document lessons learned — experience that will directly inform sound architectural judgment when building the real multi-tenant CloudDent platform, rather than guessing at multi-tenant design without first-hand production-style experience.
