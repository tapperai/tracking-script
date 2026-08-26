# Tracking Script — Environment Spinup

> **Status:** `SHIPPED`
>
> **Created:** 2026-08-26
> **Last updated:** 2026-08-26
>
> **Implemented in:** tracking-script

## Overview

This repo has no cloud infrastructure of its own — no compute, no database,
no queues, no secrets. It is a single GTM Community Template file
(`template.tpl`) plus a metadata file (`metadata.yaml`) that Google's
Community Template Gallery reads directly off this repo's default branch
(`main`). "Spinning up" this repo means cloning it and running the CI
validator locally; there is nothing to provision.

---

## Cloud Services

None. The template's only external dependency at runtime is a URL it is
permitted to inject in a customer's browser —
`https://monitor.tapper.ai/bundle.js` — which is owned and deployed by a
different Tapper service, not this repo.

## Databases

Not applicable.

## Event Stores / Message Queues

Not applicable.

## Container Orchestration / Compute

Not applicable — no process runs anywhere for this repo. The "runtime" is
GTM's own sandboxed JS engine, executing inside a customer's GTM container
once they've imported the template — Tapper does not host or operate that
execution environment.

## CI/CD

- Trigger: push or PR to `main`.
- Runner: `.github/workflows/validate.yml`, GitHub Actions
  `ubuntu-latest`.
- Steps: checkout, then `python3 scripts/validate_template.py template.tpl`
  (pure stdlib, no network, no secrets, no npm install).
- **The "deploy" is the push to `main` itself** — the GTM Community Template
  Gallery reads `metadata.yaml` + `template.tpl` directly off the default
  branch. CI does not push anywhere; it only gates what merges to `main`
  before Google's gallery can read it. There is no separate deploy job,
  container image, or release artifact.

## Cross-Repo Sync Scripts

None.

## Secrets & Configuration

None. No `.env`, no Secret Manager entries, no credentials of any kind are
used by this repo or its CI job.

## Spinup Procedure (from zero)

1. `git clone git@github.com:tapperai/tracking-script.git`
2. `python3 scripts/validate_template.py template.tpl` — confirms the
   checked-out template still validates (no other setup needed; the script
   is pure Python 3 stdlib).

That's the entire local spinup — there is no server to start and no
database to seed.

## Teardown / Disaster Recovery

Not applicable — there is no running infrastructure to tear down. Recovery
from a bad template push is: revert the commit on `main` (the gallery
re-reads the branch on its own schedule) and, if a broken version was
already published to the Community Template Gallery, follow Google's
gallery-side version-rollback process (outside this repo).

## Verification

- `python3 scripts/validate_template.py template.tpl` exits `0`.
- The GitHub Actions "Validate GTM Template" check is green on `main`.
- Manual GTM Preview check — see `TESTING.md` §3.

## Files

- `.github/workflows/validate.yml` -- the only "infrastructure" this repo
  has: the CI gate described above.
- `scripts/validate_template.py` -- the validator that gate runs.
