# {Environment / Infrastructure Name} — Environment Spinup

> **Status:** `DRAFT`
>
> **Created:** YYYY-MM-DD
> **Last updated:** YYYY-MM-DD
>
> **Implemented in:** {repo-name} {— list repos whose infra this describes}

{Use this template instead of SPEC.md when the domain is infrastructure /
environment setup rather than a product feature: GCP/cloud services,
database provisioning, event stores, message queues, container
orchestration, CI/CD, cross-repo sync scripts.}

## Overview

{What does this environment run, and for whom? One paragraph. Name the
cloud project(s) explicitly — project IDs, not nicknames.}

---

## Cloud Services

{One row per managed service. Be exact about project + region — wrong-
project assumptions are the #1 spinup failure.}

| Service | Project | Region/Zone | Resource | Purpose |
|---|---|---|---|---|
| {GKE / GCE / Cloud SQL / Memorystore / Pub/Sub / Secret Manager / GCS} | {project-id} | {region} | {cluster/instance/bucket name} | {why} |

## Databases

{Per database: engine + version, instance/host, how schema is created
(migrations tool + command), how credentials are obtained (Secret Manager
path — never inline), and any extensions required.}

- **Engine:** {Postgres NN / Bigtable / BigQuery dataset}
- **Schema management:** {e.g. `prisma migrate deploy --schema=…` / `bq` DDL scripts}
- **Credentials:** {Secret Manager secret name + accessor role}
- **Extensions / special config:** {e.g. pgvector, partitioning, clustering}

## Event Stores / Message Queues

{Queues, exchanges, topics. Who produces, who consumes, what happens to
messages when a consumer is down.}

| Queue/Topic | Broker | Producer | Consumer | Retry/DLQ behavior |
|---|---|---|---|---|

## Container Orchestration / Compute

{How code becomes a running process: GKE deployment + ArgoCD app, plain
VM + pm2, Cloud Run, etc. Include the EXACT restart/reload commands and
their footguns.}

## CI/CD

{Trigger → build → deploy chain. Where the pipeline definition lives,
what credentials it uses, what it does NOT do (e.g. "CI runs no tests —
merge IS the deploy").}

## Cross-Repo Sync Scripts

{Scripts that copy schemas/data/config between repos or systems: what
they sync, when to run them, what breaks when they're skipped.}

## Secrets & Configuration

{Every secret: name, store (Secret Manager path), which processes read
it, rotation procedure. Every non-secret env var: where it's set and how
a change is rolled out (e.g. pm2 env-cache caveat).}

## Spinup Procedure (from zero)

{The exact ordered commands to stand the environment up from nothing.
Number every step; mark the ones that are one-time vs repeatable.}

1. {…}

## Teardown / Disaster Recovery

{How to safely tear down or rebuild. What is backed up, where, and the
restore procedure.}

## Verification

{How to prove the environment is healthy end-to-end: health endpoints,
queue depth checks, smoke commands, expected log lines.}

## Files

{Infra-as-code and script paths relevant to this environment.}
