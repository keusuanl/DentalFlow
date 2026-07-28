# ADR-002: S3 for Scan Storage

## Status
Accepted

## Context

DentalFlow needs a secure place to store patient scan files (STL, ZIP, PDF). Per NFR-SEC-1 and NFR-SEC-4, only authenticated, least-privilege access to this data is acceptable, and per NFR-DATA-1, scan data must be treated with realistic (not theatrical) security: private storage, encryption at rest and in transit. S3 does not enforce these properties automatically by default  public access blocking, in-transit enforcement, and object organization all require deliberate configuration, making this a decision worth documenting rather than an assumption. Per NFR-OBS-1, it must also be
possible to reconstruct what happened to a given order, which requires a predictable, traceable object structure.

## Decision

Use a single private S3 bucket with the following controls:

1. **Block Public Access** is turned on at the bucket level and declared explicitly in
   Terraform, rather than relying on the AWS account-wide default,  this keeps the guarantee visible and enforced in our own code.
2. **Encryption at rest** uses default SSE-S3 (AWS-managed keys). **Encryption in
   transit** is enforced via a bucket policy that denies every request where the `aws:SecureTransport` condition is `false`.
3. **Object keys** follow the pattern `scans/{order_id}/{original_filename}`, so every file is easy to locate and troubleshoot by order, satisfying NFR-OBS-1. This structure also leaves a clean extension point for CloudDent: a `{clinic_id}` prefix can be inserted (`scans/{clinic_id}/{order_id}/{filename}`) later as a straightforward path insertion, not a redesign.

## Consequences

**Positive:**

- Explicitly declaring Block Public Access means this bucket cannot be made public by
  accident, regardless of account-level settings or defaults changing elsewhere.
- The `aws:SecureTransport` policy means any request over plain HTTP is denied outright
  — there is no window for a man-in-the-middle attack to intercept scan data in clear text or sniffing via wireshark etc.
- The `scans/{order_id}/{filename}` structure means troubleshooting a specific order's
  upload (e.g. "did order 456's file actually arrive?") narrows immediately to one
  predictable path, rather than searching a flat, unstructured bucket.

**Negative (accepted tradeoff):** Choosing SSE-S3 (AWS-managed keys) over SSE-KMS with a
customer-managed key means we give up direct control over key rotation policy and
key-level access logging/auditing. This would matter more in a real, fully
compliance-driven healthcare deployment, where organizations typically need to control
and audit their own encryption keys independently of the cloud provider. For
DentalFlow's PHI-lite scope (NFR-DATA-1), this level of control is not required.

## Alternatives Considered
**SSE-KMS with a customer-managed key**, instead of SSE-S3. Rejected for DentalFlow:
customer-managed KMS keys incur additional cost (per-key monthly charge plus
per-request charges) and operational overhead (key policy management, rotation
scheduling) that isn't justified for a single-tenant, PHI-lite learning project, this
directly follows from NFR-COST-1 (free-tier friendly where reasonable) and NFR-DATA-1's
explicit scoping. This is the natural upgrade path for a real production healthcare
deployment or for CloudDent at scale.
