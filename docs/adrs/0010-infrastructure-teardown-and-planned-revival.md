
**Status**

Accepted

Context

DentalFlow's original scope, infrastructure, backend, documentation, the API walkthrough, the architecture diagrams, and the incidents log, is complete. Per the infra lifecycle decision in pending-applies.md, infrastructure had been left running continuously since 2026-08-11 to support repeated cross-service integration testing. That reason no longer applies, active development has stopped, and continuing to run Multi-AZ RDS and a NAT Gateway around the clock is idle cost with no corresponding learning or demonstration value, directly against NFR-COST-1.

Two further items remain deliberately unbuilt: a CI/CD pipeline and CloudWatch observability, both already tracked as roadmap items rather than oversights. Building either against currently-running infrastructure isn't necessary, everything here is defined in Terraform, and both are additive work that can be layered on whenever they're picked back up.

Decision

Destroy all live AWS infrastructure now that the core project is feature and documentation complete. Do not spin up a separate project for CI/CD or observability. Both will be built later as direct extensions of DentalFlow, re-applying the existing Terraform modules rather than rebuilding from scratch.

This is chosen over building CI/CD and observability as standalone projects because the infrastructure, IAM scoping, and NFRs they'd need to work against already exist here, fully designed and already debugged through real incidents. A separate project would either need to reinvent a comparable backend to have something worth deploying and monitoring, or work against a much thinner, less realistic stack. Reviving a finished project later is also a more honest signal than it might first appear, it shows a project being maintained and hardened over time, not abandoned the moment its initial scope was done.

Consequences

Positive: No idle AWS cost between now and whenever this work resumes. The teardown itself required no new tooling, terraform destroy reverses exactly what terraform apply built, since nothing was ever done outside Terraform. When CI/CD and observability work resumes, the environment can be rebuilt in minutes, not redesigned.

Negative (accepted tradeoff): The live ALB URL in api-walkthrough.md will no longer resolve once torn down. This is acceptable, the walkthrough already stands as a complete, timestamped record of the system working, it doesn't need to still be running to serve as evidence. Re-running any of it live in the future would require a fresh terraform apply and fresh demo data, the same disposable-environment discipline used throughout this project's infra phase.

Known follow-up: AWS Secrets Manager schedules the RDS credentials secret for deletion rather than removing it immediately (see the incidents log). Force-deleting it at teardown time, rather than waiting out the recovery window, avoids re-hitting that same conflict on the next apply.

Alternatives Considered

Leave infrastructure running indefinitely. Rejected, there's no active development to justify the ongoing cost, and nothing about CI/CD or observability work requires infrastructure to already be live before it starts, both are designed and built in Terraform/CI config first, then applied.

Build CI/CD and observability as separate, purpose-built projects. Considered seriously. Would allow exploring a broader set of tools (Prometheus/Grafana alongside CloudWatch, for instance) and would keep each project narrowly scoped for interview conversations. Rejected for now in favor of extending DentalFlow directly, the existing IAM scoping, NFRs, and real incident history here give CI/CD and observability something genuine and specific to build against, rather than a synthetic example.