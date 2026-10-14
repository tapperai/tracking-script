# {Domain Name} — Testing Framework

> **Parent:** [{domain-name}](SPEC.md)
>
> **Script:** `y-scripts/{simulatorScript}.ts` _(if one exists)_

{One sentence: what this document covers — what flows you can test and what the simulator stands in for.}

---

## Pipeline Overview

```
{ASCII diagram of the flows you can test end-to-end, same notation as SPEC.md Architecture:}

Flow A: {name}
  Step 1 → Step 2 → Step 3

Flow B: {name}
  Step 1 → [gap — simulator fills this] → Step 3
```

---

## Prerequisites

### Required env vars (`.env.local`)

```bash
# Required connections
DATABASE_URL=...
RABBITMQ_URL=amqp://...

# Required queue names
SOME_QUEUE=queue-name

# Optional — enable extended features
BIGTABLE_PROJECT_ID=...
```

### Running consumers

```bash
# Terminal 1 — {Consumer description}
npx tsx src/consumers/rabbitmq/{path}/consumer.ts

# Terminal 2 — {Consumer description}
npx tsx src/consumers/rabbitmq/{path}/other-consumer.ts
```

### Required: {any seed data or lookups needed}

```sql
-- Example: look up a valid ID to use in tests
SELECT id FROM some_table WHERE deleted_at IS NULL LIMIT 5;
```

---

## Simulator Usage

```bash
# Interactive — prompts for required inputs
./y-scripts/{simulator}.ts

# Non-interactive — pass args directly
./y-scripts/{simulator}.ts <required-arg> <mode> [--count=N] [--option=VALUE]
```

| Mode | What it tests | Sends to |
|---|---|---|
| `{mode1}` | {description} | `{QUEUE_NAME}` |
| `{mode2}` | {description} | `{QUEUE_NAME}` |

> **Simulator design rules (for when you build/update this script):**
> - Run with no args → interactive: prompt for each required input one at a time
> - Prompt includes a lookup query so the user knows where to find valid values
> - **For multi-flow simulators, use an arrow-key selection menu** (not a text prompt) — options render as `[type]  name     desc` so the category is obvious at a glance. Use alternate screen buffer + readline raw mode. Lazy-import queue/DB libs inside the run loop to prevent connection logs during the menu
> - After each test run, print the verification SQL query with the actual test values filled in
> - Print any relevant URLs (tracker links, webhook URLs) so they can be opened directly in the browser
> - All args also work non-interactively so the script can be automated/piped

---

## Test Scenarios

### Scenario 1: {Name}

{One sentence: what this tests.}

```bash
# Interactive
./y-scripts/{simulator}.ts

# Non-interactive
./y-scripts/{simulator}.ts {arg} {mode}
```

**What happens:**
1. {Step}
2. {Step}
3. {Step — script prints verification SQL at the end}

**Verify in PostgreSQL** _(script prints this automatically):_
```sql
-- {What to check}
SELECT ...
FROM ...
WHERE ...
ORDER BY id DESC LIMIT 1;

-- Expect: {what the result should look like}
```

---

### Scenario 2: {Name}

{One sentence: what this tests.}

```bash
./y-scripts/{simulator}.ts {arg} {mode}
```

**What happens:**
1. {Step}
2. {Step}

**Verify in PostgreSQL:**
```sql
SELECT ...
```

---

### Scenario 3: {Name (manual — no simulator)}

{Use this format when a flow has no simulator and must be triggered manually.}

```bash
npx tsx -e "
const { sendToQueueLight } = require('./src/libs/rabbitmq');
sendToQueueLight(process.env.SOME_QUEUE, {
  field: 'value',
});
" --env-file .env.local
```

**Verify in logs:**
```
{ event: \"PROCESSED_SOMETHING\", ... }
```

---

## Bulk Testing

```bash
# Run N times to test accumulation / deduplication behavior
./y-scripts/{simulator}.ts {arg} {mode} --count=10
```

---

## Expected Log Events

| Consumer | Event | When |
|---|---|---|
| `consumer.ts` | `START_PROCESSING_{DOMAIN}` | Every message |
| `consumer.ts` | `PROCESSED_{DOMAIN}` | Success |
| `consumer.ts` | `ERROR_PROCESSING_{DOMAIN}` | Failure |

---

## {Other Behavior to Document}

{e.g. Deduplication, retries, idempotency — describe the behavior and how to verify it.}

```bash
# Example: run same command twice to test deduplication
./y-scripts/{simulator}.ts {arg} {mode}
# Second run should produce 0 new rows
```
