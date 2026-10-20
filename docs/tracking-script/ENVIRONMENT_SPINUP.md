# Tracking Script — Environment Spinup

> **Status:** ACTIVE
>
> **Created:** 2026-08-26
> **Last updated:** 2026-10-20
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

- Trigger (CI standard 2026-10-17): a ready PR to `main` (`opened`,
  `synchronize`, `reopened`, `ready_for_review`; a `ci:` label acts through
  `ci-label.yml`, which dispatches `tests.yml`) and the test
  batch (`test-batch.yml`: every `CI_BATCH_SIZE` merges, nightly, on demand;
  a red batch is bisected to the guilty merge). Draft PRs run nothing. There
  is no merge queue and no push run.
- Checks: `Validate template.tpl (pre-deploy gate)`, the job name, which runs
  on every ready PR in every gate mode (about 10 seconds; it stops a broken
  template before it lands), and `CI gate`, which follows the Actions variable
  `CI_GATE_MODE` (skipped under `NONE`, which counts as passing). Ruleset
  `required-checks` (id 25124315) names both for `main` but has been DISABLED
  since 2026-10-17, so GitHub requires neither today: do not merge on a red
  pre-deploy check. Never rename either.
- Runner: `.github/workflows/tests.yml`, GitHub Actions
  `ubuntu-24.04-arm`, 5-minute timeout; a newer push to a PR cancels the
  older PR run.
- Steps: checkout, then `python3 scripts/validate_template.py template.tpl
  --metadata metadata.yaml` and `node scripts/run_template_tests.mjs
  template.tpl` (pure stdlib, no network, no secrets, no npm install).
- **The "deploy" is the `versions` list in `metadata.yaml`**: the Gallery serves the `template.tpl` of the commit named by its FIRST `sha` (newest first; Google picks up a new entry in typically 2-3 days). A push to `main` that changes `template.tpl` without a new first `metadata.yaml` entry reaches no customer. Imported templates never auto-update: each container that imported the template must accept the update and publish. CI does not push anywhere; there is no deploy job, container image or release artifact.

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

Not applicable: there is no running infrastructure to tear down. To recover from a bad template release, revert the bad `template.tpl` change in a new commit on `main`, then in a second commit add that revert commit's full sha as a NEW first `metadata.yaml` `versions` entry, keeping the bad version listed below it (Google: every published version stays listed, newest first), and merge with a merge commit. The Gallery picks it up in typically 2-3 days; every container that already accepted the bad version must accept the new one and publish. To withdraw the template from the Gallery instead, delete `metadata.yaml` or `LICENSE` (Google's documented removal path).

## Verification

- `python3 scripts/validate_template.py template.tpl` exits `0`.
- The `Validate template.tpl (pre-deploy gate)` check is green on the PR
  (and on the latest test-batch run on `main`).
- Manual GTM Preview check — see `TESTING.md` §3.

## Files

- `.github/workflows/tests.yml` (+ `test-batch.yml`) -- the only "infrastructure" this repo
  has: the CI described above.
- `scripts/validate_template.py` -- the validator that gate runs.
