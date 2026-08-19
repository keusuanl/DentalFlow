# ADR-0007: Python Runtime Version and PostgreSQL Driver Choice

## Status
Accepted

## Context
Local backend development began on Python 3.14, the newest available interpreter at
the time. Installing the initially planned dependency set failed: `psycopg2-binary`
had no prebuilt wheel for Python 3.14's ABI (cp314), and pip's fallback to building
from source required `pg_config` (PostgreSQL dev headers), which was not installed.
Retrying with `psycopg[binary]` (psycopg3) succeeded, since psycopg3 already had
cp314 wheels published. Shortly after, `pydantic-core` hit an equivalent missing-wheel
error on the same Python version, confirming this was not an isolated one-package
issue but a pattern: a brand-new CPython release with immature third-party wheel
support across the ecosystem.

## Decision
Two related decisions:

1. **Recreate the local dev venv on Python 3.12**, a mature, widely-adopted release
   with broad, stable wheel availability across the dependency tree, rather than
   continuing to chase wheel availability package-by-package on 3.14.
2. **Use psycopg3 (`psycopg[binary]`) rather than psycopg2** as the PostgreSQL driver,
   even after moving to Python 3.12 where psycopg2 wheels would have worked. psycopg3
   is the actively maintained successor, was already proven working, and required no
   further changes once the underlying Python version problem was resolved.

## Consequences

**Positive:** Eliminated an entire class of recurring wheel-availability errors at the
root cause (the Python version itself) rather than patching each affected package
individually - a direct application of eliminating toil rather than repeatedly
absorbing it. Python 3.12 matches what the Docker base image (`python:3.12-slim`) and
ECS Fargate container both use, keeping local dev, Docker, and production environments
on an identical Python version throughout the project.

**Negative (accepted tradeoff):** Lost access to Python 3.14-specific language
features, though none were in use or needed at this project's scope. psycopg3's
connection string dialect (`postgresql+psycopg://`) differs from psycopg2's
(`postgresql+psycopg2://`) - a detail that must be remembered by anyone extending this
project's SQLAlchemy configuration, though it is fully documented in `db/base.py` and
`.env.example`.

**Related incident:** the same URL-encoded RDS password (containing literal `%`
characters) that had no impact on the SQLAlchemy connection string itself later broke
Alembic's `env.py`, because `configparser` (used internally by `alembic.ini`) treats
`%` as interpolation syntax. Fixed by escaping `%` as `%%` before passing the URL into
`config.set_main_option()`. Not a driver issue, but discovered in the same area of the
codebase and worth cross-referencing here for anyone debugging Alembic against a
real RDS password containing special characters.

## Alternatives Considered
**Stay on Python 3.14 and work around each missing wheel** (install build toolchains,
compile from source as needed). Rejected: treats a systemic, recurring problem
(ecosystem lag behind a brand-new CPython release) as a series of unrelated one-off
issues, and this project's own goal is building senior-engineer habits, which includes
recognizing when a "fix it as it comes up" approach is actually accumulating toil that
a single upstream decision (the runtime version) can eliminate outright.
