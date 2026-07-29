# ADR-003: SQS + SNS for Lab and Clinic Notification

## Status
Accepted

## Context
Per NFR-REL-1, a failed or dropped lab notification is a critical failure, not a minor
bug. It can break trust between the practice and their patients, and across the lab
team, leaving a whole pipeline invisible to the people who need to act on it. Reliable
notification delivery is directly tied to customer and business trust. SNS alone
provides best-effort delivery: if a delivery attempt fails, there is no built-in retry
or durable holding of that message. It can be silently lost. This does not satisfy
NFR-REL-1.

## Decision
Notification delivery must be reliable and must retry if a delivery attempt fails.
This is why SNS alone is not sufficient, and why SQS is introduced as a durable buffer
behind it. The flow works as follows:

- S3 tells an **upload SQS queue** "a file has arrived" (per the existing data-flow
  design). The backend consumes this to update the order status in RDS.
- Once the backend has updated the database, it tells **SNS** "notify the lab."
- SNS fans this out into a **separate notification SQS queue**, so the message is
  durably held until a consumer (lab dashboard/notification service) actually processes
  it. The lab never silently misses a case.

**Two separate queues are used**, one for upload events and one for lab/clinic
notifications, rather than a single shared queue distinguishing message types via a
conditional field (e.g. `type: upload_received` vs `type: notify_lab`). Handling both
purposes in one queue would require every consumer to branch on message type, adding
complexity that runs counter to this project's scope of avoiding unnecessary
complexity, and would make debugging and monitoring harder to reason about. A failure
in one queue could be masked or confused with the other. Splitting them gives each
queue a single, clear responsibility, its own DLQ, and independent monitoring and
alerting. This costs essentially nothing extra. Unlike NAT Gateway, SQS has no idle
hourly charge. Cost is per-message, so a second queue does not meaningfully affect
NFR-COST-1.

**Dead Letter Queue (DLQ):** each queue is paired with its own DLQ, aligning with
NFR-OBS-1 (auditable, traceable activity). Concrete scenario: if RDS is temporarily
unavailable (e.g. during a maintenance window), the backend consumer will fail to
process an upload-event message. It can't update the order status. Since the message
is never deleted after repeated failed processing attempts, SQS moves it to the DLQ
after a configured number of retries, where it is safely parked instead of being lost
or looping forever. From there, the specific failed order can be inspected, the root
cause (e.g. RDS availability) resolved, and the message redriven back into the main
queue for reprocessing.

## Consequences

**Positive:** Notification delivery is durable. A transient failure (lab dashboard
briefly down, a processing error) no longer means the lab or clinic silently never
finds out about a case. DLQs give a concrete, inspectable audit trail for anything that
repeatedly fails, directly satisfying NFR-OBS-1. Separating upload and notification
queues keeps each concern independently scalable, monitorable, and debuggable.

**Negative (accepted tradeoff):** More moving pieces than a single-queue design. Two
queues, two DLQs, two sets of subscriptions and policies to configure and reason about.
This is a deliberate, low-cost tradeoff (SQS has no idle charge) in exchange for
clearer operational boundaries, consistent with how real-world systems separate
concerns by responsibility rather than by minimizing resource count.

## Alternatives Considered
**A single shared queue for both upload events and lab notifications**, distinguished
by a message-type field. Rejected. This pushes type-branching complexity onto every
consumer, makes a failure in one workflow harder to distinguish from a failure in the
other, and complicates DLQ inspection since a parked message's cause is less
immediately clear without first checking its type. Two queues is standard practice for
distinguishing genuinely different event types, and the cost difference is negligible
at this scale.
