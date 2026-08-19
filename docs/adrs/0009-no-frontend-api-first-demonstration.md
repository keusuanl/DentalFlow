# ADR-0009: No Frontend, API First Demonstration

## Status
Accepted

## Context
data-flow.md originally specified a React and Vite frontend as part of the
architecture. Before building it, the actual value it would add was reconsidered
against this project's stated purpose, demonstrating senior engineering habits, cloud
engineering depth, and DevOps or SRE thinking, not full stack breadth.

A frontend would add no evidence toward that goal. It demonstrates a different skill
set entirely, one this project has explicitly deprioritized from the start, see the
project's original scope framing around backend and frontend being weaker areas not
targeted for deep investment here. Research into real platform engineering, SRE, and
DevOps portfolio projects, and how experienced engineers in these roles present their
own work, consistently showed a pattern, these projects rarely include a full frontend.
They focus on infrastructure, security, and operational reasoning, with the API or
system itself demonstrated directly.

## Decision
DentalFlow will not have a frontend. The system is demonstrated and verified entirely
through direct API interaction, curl, and standard terminal tooling, documented in a
dedicated API walkthrough (docs/architecture/api-walkthrough.md) covering every real
flow already proven live during development, authentication, order creation, presigned
S3 upload and download, the SQS driven status transition, and SNS notification
delivery.

## Consequences

**Positive:** Time and effort stay concentrated on the areas this project actually
exists to demonstrate. A terminal driven walkthrough is arguably a more honest and more
relevant demonstration of the target skill set (Cloud Engineer, Platform Engineer,
DevOps Engineer, SRE, Cloud Security Engineer) than a UI would be, it shows direct
comfort with the same tools and verification habits used throughout this project's
troubleshooting incidents, curl, AWS CLI, reading raw request and response data.

**Negative (accepted tradeoff):** Less immediately accessible to a non-technical
reviewer, who would need to read documented request and response examples rather than
click through a visual interface. Also means data-flow.md's original architecture
diagram needed revision, since it previously named a frontend as a first class
component.

## Alternatives Considered

**Build the originally planned React and Vite frontend.** Rejected, for the reasoning
above, it does not serve this project's actual learning goals and target roles, and
would cost real session time (estimated four to six hours) better spent on
infrastructure hardening, documentation, or the incidents compilation already planned
for the project's close.

**A minimal frontend anyway, just to visually round out the project.** Considered.
Rejected on the same reasoning, if built, it would exist purely for a moment of visual
completeness, not for any actual demonstration value toward this project's stated
goals.
