# {Domain Name}

> **Status:** `DRAFT`
>
> **Created:** YYYY-MM-DD
> **Last updated:** YYYY-MM-DD
>
> **Implemented in:** {repo-name} {— list repos that have working code, omit if nothing is implemented yet}

{If this domain spans multiple repos, add cross-repo references:}

> **Cross-repo:** {Brief description of what lives in the other repo.}
> - **{Repo name}:** `{repo}: docs/{path}/SPEC.md` — {what it covers}

{Or if this spec has a counterpart in another repo:}

> **{Repo name} counterpart:** `{repo}: docs/{path}/SPEC.md` — {what the counterpart covers}

## Overview

{What is this and why does it exist? One paragraph.}

---

## Architecture

```
{Sequence diagram for multi-system communication:}

System A                 System B                 System C
    |                       |                        |
    |--- Action ----------->|                        |
    |                       |-- Forward ------------>|
    |                       |<-- Response -----------|
    |<-- Result ------------|                        |

{Tree/arrow notation for pipelines:}

Source System
├── QUEUE_NAME ──> consumer
│   ├── Processing step 1
│   └── Forwards to NEXT_QUEUE ──> downstream pipeline
│
└── ANOTHER_QUEUE ──> consumer
    └── Processing step

{Data hierarchy / entity model:}

Parent Entity (key)
├── Child Entity (key) ──── description
│   └── Grandchild Entity (key)
└── Other Child

{Key flows with branching:}

1. Step description
   ├── Condition A ──> outcome
   └── Condition B ──> outcome
2. Next step
```

---

## Schema

{Data model — SQL tables, enums, indexes, Bigtable families, protobuf types.}

### Stored credentials

{One row per credential this domain stores; delete the section if none. Kind and home follow the secrets rule (root `CLAUDE.md`, CONFIG STANDARD): Tapper's own secrets live in Secret Manager only; a secret a customer, partner or person gives us lives in this service's DB, KMS-encrypted per value (`tokenVault` pattern), with a masked preview column, kept out of BigQuery and CDC; never Secret Manager, never plaintext.}

| Credential | Kind (OURS / GIVEN TO US) | Where it lives (secret name, or table.column + preview column + KMS key) |
|---|---|---|
| | | |

---

## Contracts

{API endpoint definitions.}

| Method | Path | Summary |
|--------|------|---------|
| | | |

---

## Routes

{Route handlers with middleware, auth.}

---

## Queues

{RabbitMQ/BullMQ consumers with message interfaces and processing steps.}

### `QUEUE_NAME` (RabbitMQ)
**Consumer:** `src/consumers/...`

**Message fields**: ...

**Processing**:
1. Step
2. Step

---

## Operational Procedures

{Migration steps, sync workflows, deployment processes, data pipeline procedures. Document exact commands and order of operations for making changes in this domain.}

### {Procedure Name}

1. Step — `command to run`
2. Step — `command to run`
3. Verify — what to check

---

## Edge Cases

- **{Scenario}**: {How we handle it.}

---

## Testing

{How to test this feature end-to-end locally. Include:
- Required env vars
- Which consumers/services must be running
- The exact script commands to run for each test scenario (from `y-scripts/` or manual queue sends)
- What to verify in PostgreSQL / Bigtable / BigQuery / logs after each run
- Expected log events and their meanings

If there's a dedicated `y-scripts/` simulator for this domain, document all its modes here.
If the feature has no test script yet, document the manual steps to trigger and verify each flow.}

### Prerequisites

```bash
# Required env vars
# Running services
```

### {Scenario name}

```bash
# Command
```

**Verify:**
```sql
-- Verification query
```

---

## Files

- `path/to/file.ts` -- description

---

## Remaining Work

{Numbered list of what's designed but not yet implemented. Include repo, what, and enough context to pick it up later. Remove this section when everything is shipped.}

1. **{repo}: {short title}** — {description of what needs to be done}

---

*Delete any sections above that aren't relevant to this domain.*
