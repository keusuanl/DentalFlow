# DentalFlow, Incidents and Troubleshooting Log

This is a record of things that actually broke while building DentalFlow, why
they broke, and what fixed them. Nothing here is theoretical. Every entry
happened on real infrastructure or real code, most of them were only found by
running the system and watching it fail, not by reading documentation first.

If you're reviewing this project for hiring purposes, this document is
probably more useful than the clean parts. Anyone can demo a working system.
This is the part that shows how I actually debug.

Each entry follows the same shape: what happened, what actually caused it,
how it got fixed, and what I'd do differently or watch for next time.

## IAM and access control

### ECS task role had zero S3, SQS, or SNS permissions

**What happened:** The first time the deployed app tried to generate a
presigned S3 upload URL against real AWS, it failed. So did the SQS consumer.
So did the SNS publish call. All three, on the same day, once real traffic
hit the live ECS task instead of local dev.

**Root cause:** Local development had always run against my own AWS
credentials, which had broad access. The ECS task role, the identity the
app actually runs as in production, had never been granted any of these
permissions. It looked fine locally because local dev was never using that
role.

**Fix:** Three separate scoped inline policies, one for S3 (`PutObject`,
`GetObject`, restricted to the `scans/*` prefix), one for SQS (`ReceiveMessage`,
`DeleteMessage`, `GetQueueAttributes`, restricted to the upload queue), one for
SNS (`Publish`, restricted to the notification topic). No wildcards.

**Lesson:** Testing against your own credentials tells you the code works.
It doesn't tell you the deployed identity can actually do anything. That gap
only shows up once you test against the real, deployed role.

### Local dev IAM user missing iam:GetRolePolicy

**What happened:** Right after fixing the issue above, `terraform apply`
failed with an AccessDenied error while trying to attach one of those new
inline policies.

**Root cause:** Terraform needs to read back a policy after creating it, and
my local dev IAM user's narrowly scoped role-management policy didn't include
`iam:GetRolePolicy`. It had been scoped months earlier for a different, more
limited purpose.

**Fix:** Added the missing action to the existing policy, same
`dentalflow-*` resource restriction as everything else, nothing broadened
beyond what was actually needed.

**Lesson:** Narrow IAM scoping isn't a one-time setup, it's something you keep
running into as the project grows. Each new integration surfaces its own
missing permission. That's expected, not a sign the original scoping was
wrong.

## Infrastructure and deployment

### RDS backup retention rejected by the free tier

**What happened:** `terraform apply` failed with a `FreeTierRestrictionError`
when trying to set a 7-day backup retention period on RDS.

**Root cause:** The AWS account's free tier caps backup retention lower than
what I'd planned. I only found this by actually running the apply, not by
reading AWS's documentation beforehand.

**Fix:** Dropped retention to 1 day, RDS's own minimum. Documented as an
explicit, known limitation, not a silent compromise, since a real production
setup would use something like 7 to 35 days.

### Secrets Manager wouldn't let a new secret reuse an old name

**What happened:** After destroying and re-applying the full infrastructure,
`terraform apply` failed on the database credentials secret.

**Root cause:** AWS Secrets Manager doesn't delete a secret immediately when
you ask it to, it schedules deletion after a recovery window, 30 days by
default. My earlier `terraform destroy` had scheduled deletion but not forced
it, so the name was still reserved.

**Fix:** `aws secretsmanager delete-secret --force-delete-without-recovery`
to free the name immediately, then re-ran the apply. Terraform picked up from
existing state and only recreated the two missing resources.

**Lesson:** Destroying infrastructure doesn't always mean it's gone
immediately. Some AWS services have built-in recovery windows that will
quietly block your next apply if you don't account for them.

### ALB target group replacement failed on redeploy

**What happened:** Updating the ECS module hit a conflict trying to replace
the target group.

**Root cause:** The target group had a fixed name. Terraform's default
behavior is to destroy the old resource before creating the new one, but a
fixed name means the new one collides with the old one before it's gone.

**Fix:** Switched to `create_before_destroy` with a `name_prefix` instead of
a fixed name, so the new target group can exist alongside the old one during
the swap.

### Container crashed immediately after first deploy

**What happened:** The first real deployment to ECS Fargate came up and
immediately crashed, over and over, on every task restart.

**Root cause:** Required environment variables were never wired into the
task definition, the app couldn't start without them and failed fast.

**Fix:** Added the missing environment variables to the task definition.
Deliberately left them as plain (non-Secrets-Manager) environment variables
at this stage, to get a working deployment first and harden secrets handling
second, tracked separately.

### RDS unreachable from my own laptop

**What happened:** After migrating the schema locally against Docker
Postgres, I needed to run the same migration against the real, deployed RDS
instance. Direct connection attempts from my laptop just hung.

**Root cause:** This is working as designed, RDS sits in private subnets
with no route from the public internet. That isolation is the whole point.

**Fix:** Used ECS Exec to open a shell inside a running Fargate task, which
already has network access to RDS, and ran the migration from there instead
of trying to reach RDS directly.

### Alembic broke on a real RDS password with a percent sign

**What happened:** Migrations worked fine locally, but failed against real
RDS with a `ValueError` that made no sense at first glance.

**Root cause:** The generated RDS password contained a literal `%`
character. Alembic passes the database URL through Python's `configparser`
internally, which treats `%` as string interpolation syntax. The same
password caused zero issues in the actual SQLAlchemy connection string,
only in Alembic's config handling.

**Fix:** Escaped `%` as `%%` before handing the URL to
`config.set_main_option()`. Only affects how the config parser reads the
string, not the real connection.

## Application code

### SQS consumer crashed on its first real message

**What happened:** The consumer worked fine in every local and dev test.
The moment it processed a real message in production, it crashed with
`NoReferencedTableError`.

**Root cause:** The `orders` table has a foreign key to `users`. SQLAlchemy
needs every related model imported somewhere in the running process for that
foreign key to resolve when it flushes to the database. The consumer file
only ever imported `Order`. It worked everywhere else because `main.py`
imports both models transitively through its routers, an import path the
standalone consumer process doesn't share.

**Fix:** Added the same import pattern already used correctly in
`alembic/env.py`.

**Lesson:** A working import graph in one part of an app doesn't mean it's
working everywhere. Anything that runs as its own process needs its own
complete set of imports, you can't assume it inherits what another entry
point already loaded.

### A real SQS message got permanently lost during debugging

**What happened:** While reproducing the crash above live, inside a running
container, the one real message sitting in the upload queue got consumed and
deleted before the fix was in place.

**Root cause:** The consumer's `finally` block deletes every received
message unconditionally, regardless of whether processing succeeded. This
was already a known, documented simplification, not a new bug, DLQ-aware
retry logic hadn't been built yet. Debugging live against a queue with
exactly one message in it is what turned a known gap into an actual lost
message.

**Fix:** No fix to the message itself, it's gone. The affected order was
abandoned rather than force-completed, and a fresh order was used to
continue testing.

**Lesson:** A known limitation you've documented but not yet fixed can still
cause real damage the first time you interact with the system in a way that
exercises it. Documenting a gap isn't the same as it being safe to ignore.

## Local development environment

### Local Postgres didn't survive a restart

**What happened:** After a WSL2/Docker restart, a request that touched the
database returned a 500 error with no obvious cause.

**Root cause:** The local Postgres container had been started with
`docker run`, not `docker start`, and had no restart policy. The container
simply wasn't running anymore.

**Fix:** Ran `docker start dentalflow-postgres` instead of trying to
recreate it, confirmed via `docker ps -a` that the container existed but was
stopped, not missing.

### Python 3.14 broke dependency installation

**What happened:** Installing the initial planned dependencies failed,
`psycopg2-binary` had no prebuilt wheel for the Python version in use, and
building from source needed PostgreSQL headers that weren't installed.
Shortly after, `pydantic-core` hit the same kind of failure.

**Root cause:** Local development had started on Python 3.14, the newest
release available at the time, which the broader package ecosystem hadn't
caught up to yet. This wasn't one bad package, it was a pattern.

**Fix:** Recreated the local virtual environment on Python 3.12, a mature,
widely supported release, and switched to `psycopg[binary]` (psycopg3)
instead of continuing to chase wheel availability package by package.

## Process and tooling

### The repo was never actually pushed to GitHub

**What happened:** After finishing the README and architecture diagram, a
routine `git push` revealed that `git remote -v` returned nothing at all.

**Root cause:** The entire project, dozens of commits of real infrastructure
and backend work, had only ever existed locally. No remote had ever been
configured.

**Fix:** Created the GitHub repository, added it as a remote, and pushed
with `git push -u origin main`.

**Lesson:** A clean local commit history feels like progress, and it is, but
it isn't the same as the work actually existing anywhere reviewable. Worth
checking `git remote -v` early, not assuming it's configured just because
commits have been working fine.

### A diagram silently failed to render on GitHub

**What happened:** An architecture diagram displayed fine locally but showed
a broken image on GitHub, and even GitHub's own direct image viewer failed
to load it.

**Root cause:** The file was saved as WebP, then renamed with a `.png`
extension. The extension doesn't change the actual file format, `file
diagram.png` confirmed it was still WebP data underneath.

**Fix:** Converted it properly with `dwebp`, then verified the result
genuinely said `PNG image data` before committing it again.

**Lesson:** A file extension is a label, not a guarantee. If an image
renders locally in one tool but fails somewhere else, checking the file's
actual format takes ten seconds and rules out an entire category of guessing.