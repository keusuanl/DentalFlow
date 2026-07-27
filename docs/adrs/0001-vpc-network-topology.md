# ADR-001: VPC Network Topology (Availability Zones, Subnets, NAT Strategy)

## Status
Accepted

## Context
DentalFlow's application must tolerate a single-data-center-level outage — per
NFR-REL-2, the system must survive the loss of a single compute instance without full
service outage. Achieving this requires spreading workloads across multiple Availability
Zones (AZs), since an AZ is effectively an independent physical data center within an
AWS region.

ECS Fargate tasks and the RDS database must not be directly reachable from the internet,
requiring placement in private subnets with no inbound route from an Internet Gateway.
However, resources in private subnets still require outbound internet access for
operations such as pulling updated container images from ECR, applying OS-level
package updates, and calling external APIs — this outbound path requires a NAT Gateway.

NAT Gateways are billed hourly per gateway, plus per GB of data processed. Running one
NAT Gateway per AZ (the production best-practice pattern, avoiding any single point of
failure for outbound traffic) doubles this cost. Per NFR-COST-1 (free-tier friendly
where reasonable), this cost must be weighed against the actual risk being avoided.

## Decision
Deploy 2 Availability Zones, each with one public and one private subnet (4 subnets
total). A single NAT Gateway is deployed in one AZ's public subnet; both private
subnets route their outbound internet traffic through this shared NAT Gateway, rather
than deploying one NAT Gateway per AZ.

## Consequences

**Positive:** Spreading ECS and RDS across 2 AZs satisfies NFR-REL-2 — the loss of a
single AZ does not take down the whole application, since compute and database
resources are duplicated in the second AZ (RDS Multi-AZ standby). Using a single shared
NAT Gateway rather than one per AZ halves NAT Gateway cost, directly supporting
NFR-COST-1.

**Negative (accepted risk):** If the AZ hosting the shared NAT Gateway experiences an
outage, both private subnets lose outbound internet access for the duration. This is a
bounded, not catastrophic, risk: inbound traffic to already-running ECS tasks (via the
load balancer) does not depend on the NAT Gateway, so the live application continues
serving existing users normally. What breaks during a NAT outage is outbound-dependent
operations specifically — e.g. pulling a new container image mid-deployment, or calls
to external APIs. This narrower blast radius is what makes the cost tradeoff acceptable
for DentalFlow's scope.

## Alternatives Considered
**One NAT Gateway per AZ** (production best practice). Rejected for this project's
scope: doubles NAT cost for a risk (temporary loss of outbound-only operations during
a single AZ outage) that does not interrupt the live application's ability to serve
existing traffic. This is the natural upgrade path if DentalFlow's traffic or
reliability requirements grow, or for the future multi-tenant CloudDent platform.
