# Document First Development

> Write the spec. Then write the code.

Every part of the project — whether it's a product feature, a data pipeline, or shared infrastructure — gets documented before it gets implemented. After it ships, the spec becomes the living documentation of what's running in production.

---

## Why

1. **You can't implement what you can't describe.** If the spec has gaps, the code will too.
2. **AI-assisted development demands it.** AI implements from specs. Better spec = better code = fewer iterations.
3. **Production knowledge stays in the repo.** Not in Slack threads, not in someone's head. In `docs/`.

---

## The Loop

```
SPEC ──────> REVIEW ──────> IMPLEMENT ──────> VERIFY
 │              │                │                │
 │  Write the   │  Walk through  │  Build from    │  Does the code
 │  full spec   │  edge cases,   │  the spec      │  match the spec?
 │  first.      │  challenge it. │  directly.     │  Ship it.
 │              │                │                │
 └──────────────┴────────────────┴────────────────┘
```

---

## The Development Lifecycle

The loop above is *what* document-first asks for. **How** you carry each phase
out — the actual working discipline — is captured in a set of reusable
methodology skills (slash-command skills, available in every repo). This
section maps those skills onto the loop so you know which one to reach for at
each stage. **It changes nothing about the document-first contract itself** —
the spec gate, the status lifecycle, the backlog rules, and the injected
CLAUDE.md block are all exactly as described elsewhere in this file. The
lifecycle is *guidance for executing the work*, not a new set of required
steps, and it does not alter what any repo must build.

```
            ┌─────────────────────── SPEC ───────────────────────┐
            │                                                      │
   brainstorming ──> writing-plans                                │
   (interrogate      (turn the approved spec into a bite-sized,    │
    intent before     TDD-shaped, exact-path task list)           │
    the spec)                                                      │
            │                                                      │
            ▼                          IMPLEMENT                   │
   tdd-workflow ───────> executing-plans  /  subagent-driven-development
   (failing test         (work the plan task-by-task, OR dispatch
    first, then           a fresh subagent per task with review
    minimal green)        between each)                            │
            │                                                      │
            ▼                           VERIFY                     │
   requesting-code-review ──> verification-before-completion ──> finishing-a-development-branch
   (fresh reviewer on a       (run the gates, read the REAL        (decide merge / PR /
    precise SHA range)         exit code BEFORE claiming done)      keep / discard; clean up)
```

| Stage | Skill | When to reach for it |
|-------|-------|----------------------|
| Before the spec | `brainstorming` | Request is vague or under-scoped — interrogate intent, constraints, and alternatives. Output feeds the spec. |
| Spec → plan | `writing-plans` | An `APPROVED` spec exists and the work is non-trivial — turn it into an exact-path, TDD-shaped task list before touching code. |
| Implement (test) | `tdd-workflow` | Fixing a reported bug (regression test first) or adding behavior to Tier-1 code — failing test first, watch it fail for the right reason, then minimal code to green. |
| Implement (drive) | `executing-plans` | You have a written plan and are driving it yourself, end-to-end, with review checkpoints. |
| Implement (delegate) | `subagent-driven-development` | The plan is a set of mostly-independent tasks and you want a fresh subagent per task with two-stage review, no human in the loop between tasks. |
| Verify (review) | `requesting-code-review` | A task or feature is done — dispatch a fresh `code-reviewer` against a precise git SHA range before merging. |
| Verify (gates) | `verification-before-completion` | About to claim done / commit / open a PR / bump a digest — run the verification command and read its real exit code FIRST. |
| Integrate | `finishing-a-development-branch` | The branch is implemented and green — decide merge / PR / keep / discard and clean up the worktree safely. |

These skills are **methodology, not policy.** They tell you how to do the work
well; they never override a repo's own CLAUDE.md, its required functionality, or
the document-first rules in this file. Reach for the one that fits the stage
you're in; skip the ones that don't apply (a one-line config change needs none
of them). The mandatory parts of the workflow remain exactly what the
**Rules** and **Implementation** sections below describe.

---

## Bug-fix writeup convention

Specs describe the happy path. Bug fixes accumulate the knowledge that specs don't carry: why the code was wrong in the first place. To make that knowledge stick, end every bug-fix reply with a short, labelled block — **regardless of fix size**. This applies across every repo that pulls this template.

```markdown
### Root cause
<The underlying reason, not the symptom. If multiple factors contributed, list
them. Include the diagnostic path if the cause was non-obvious so the next
reader doesn't redo the hunt.>

### Fix
<What changed, with file_path:line_number references. Note whether the fix was
surgical or a refactor, and why the other option was rejected.>

### Future mitigations
<Anything that would catch this earlier or prevent recurrence: a test, a type,
a lint rule, an assertion, a spec update, a CI gate, a CLAUDE.md rule, a
migration-ordering note. Say "none — one-off" when nothing applies. Do not
invent mitigations to fill space.>
```

**Placement** — end of the reply, after the summary of what you did. That way the user can skim the summary for "is it fixed?" and drop into the writeup only when they want the why.

**Non-negotiable cases** — schema drift, data-loss bugs, race conditions, auth/session bugs, migration issues, production incidents. These always get at least one future mitigation; "one-off" is not an acceptable answer.

**Where bug fixes land in specs** — if the bug fix reveals that a spec is wrong or incomplete, update the spec in the same commit. Spec + fix ship together so the living documentation stays honest. Add the root-cause summary to the spec's "Edge Cases" section if it's a class of bug that could recur.

---

## Conventions a spec must pin down

### Enum / fixed-value casing

Any value with a **fixed, known domain** (a status, a decision, a role, a type) uses **`UPPER_SNAKE_CASE`** — the cross-language standard (Protocol Buffers / gRPC style guide; Postgres `CREATE TYPE … AS ENUM`): `'ACTIVE'`, `'PENDING_DELETE'`, `'BLOCK'`. Distinct from JSON keys (snake_case) and free text (no rule). **Never mix cases in one enum**; migrating a legacy lowercase enum is a deliberate repo-wide change (DB backfill + comparisons + contracts), never piecemeal — new enums use `UPPER_SNAKE`.

**Enums WE define/own → `UPPER_SNAKE_CASE`.** The trigger is *who owns the value
set*, not whether the concept is external. If we define or map the domain it's
`UPPER_SNAKE_CASE` even when a value names a third-party concept — e.g.
`GOOGLE_SEARCH`, `META_ADS` (we own the mapping).

**Values whose vocabulary an external system owns stay AS THEY COME.** When the
provider decides the value set — whether we store it in a free-text column OR
mirror it in a validation enum (`z.enum` of an external protocol's literal
values) — keep each value exactly as delivered; do NOT force it to
`UPPER_SNAKE`. Re-casing corrupts joins/lookups against the source AND breaks
wire compatibility when the enum validates provider payloads. The canonical
example is **MMP data** (Adjust / AppsFlyer / Branch / Singular): activity-kind,
event names, network/campaign labels — and the external-protocol vocab enums
that validate them (e.g. chaos's `MmpProvider` / `MmpEventKind` / `Platform`).
(Rule of thumb: *we* declared the domain → UPPER; the *provider* decides the
value → as-is, even if we wrap it in an enum for validation.)

### Binary-classifier label spec (ML specs)

A binary model's spec must DECLARE the label semantics — never assume them:

- `target_column` — the label column.
- `positive_class_name` (what label **1** means, e.g. `"converted"`) + `negative_class_name` (what **0** means).
- `positive_is_good` — is label **1** the *desirable* outcome? **1 is always the positive class = the event of INTEREST, NOT necessarily "good"** (fraud and conversion are both `1`). Desirability is a *separate, declared* fact.
- The action follows the polarity: **1=bad → block** on a high score; **1=good → never block**. Serving is always **score ≥ threshold** (define the label so `1` is the event you act on; a reversed `≤` rule is an exploration view, not a serving mode).

This spec travels with the model end-to-end (dataset → model → deployment → inference).

---

## Folder Structure

```
document-first-template/         # Source of truth (git submodule)
├── README.md                    # Setup guide (what you see on GitHub)
├── PROMPT.md                    # AI entry point for setup + sync
├── DOCUMENT_FIRST.md            # This file — the approach
└── _templates/
    ├── SPEC.md                  # Template for new feature/domain specs
    ├── TESTING.md               # Template for standalone testing framework docs (complex pipelines)
    ├── ENVIRONMENT_SPINUP.md    # Template for environment spinup guide
    ├── BACKLOG.md               # Template for docs/BACKLOG.md (Backlog Discipline)
    └── README.md                # Template for docs/README.md

docs/
├── DOCUMENT_FIRST.md            # Synced from template
├── README.md                    # Index — every domain and its status
├── BACKLOG.md                   # Living TODO list (see Backlog Discipline block)
│
├── {domain}/                    # One folder per domain
│   └── SPEC.md
│
├── {group}/                     # Grouped domain — parent SPEC.md + subdomains
│   ├── SPEC.md                  # Core functionality
│   ├── {subdomain}/SPEC.md
│   └── ...
└── ...
```

**One folder per domain. Groups allowed for related domains.**

Every major concept in the codebase gets its own folder at `docs/{domain-name}/`. Related domains can be grouped under a parent folder — the parent has its own `SPEC.md` for the core functionality, and subdomains live in subfolders with their own `SPEC.md`.

Inside each folder: flat `.md` files. `SPEC.md` is always the main entry point. If a domain grows large, split sections into additional `.md` files next to it and link from SPEC.md.

---

## Spec Lifecycle

Every spec carries a status at the top:

| Status | Meaning |
|--------|---------|
| `DRAFT` | Being written. Not reviewed yet. |
| `APPROVED` | Reviewed. Ready for implementation. |
| `IN PROGRESS` | Currently being implemented. |
| `SHIPPED` | Live in production. Spec is now the living documentation. |
| `DEPRECATED` | Replaced or removed. Kept for history. |

---

## Backlog

`docs/BACKLOG.md` is the single living list of every TODO the user has called out for this repo, **including ones that have already shipped**. Specs describe *what we're building*; the backlog records *what the user asked for and where it stands*.

- When the user asks for something new, capture it in `docs/BACKLOG.md` *before* starting work — under the right priority (`P0` / `P1` / `P2`).
- When something ships, **don't delete it** — move it under `## Done` with a one-line note + the date so we can audit what landed and when.
- Items that exist as code but the user has not yet seen working live in `## P0 — needs verification`.
- Never silently drop a request. If you push back on scope, write the rationale inline next to the entry.
- Treat `docs/BACKLOG.md` as authoritative when the user asks "did you do X" — search there first before re-reading code or git log.

Per-repo backlogs always live at `docs/BACKLOG.md` inside the repo they describe. If this repo is a sub-repo inside a multi-repo umbrella, cross-cutting items that span multiple repos go in the umbrella repo's top-level `BACKLOG.md` instead — keep per-repo items in the per-repo file and umbrella-wide items at the umbrella root.

---

## Implementation Scope

Specs must reflect what is actually implemented in code — not just what is designed. This keeps documentation honest and prevents confusion about what's real vs planned.

### Spec-level scope

Every spec header includes an **Implemented in** field listing which repos have working code:

```markdown
> **Implemented in:** back-end
```

Or for multi-repo features:

```markdown
> **Implemented in:** back-end, tracker
```

If the spec is `APPROVED` or `DRAFT` with no implementation yet, omit the field.

### Section-level markers

When a spec mixes implemented and planned content, mark planned sections with a callout at the top:

```markdown
## Service

> **PLANNED** — Designed but not yet implemented.
```

This tells anyone reading the spec (human or AI) to skip this section during implementation reviews and not to expect matching code.

### Remaining work

When parts of a feature are deferred (e.g., implemented in one repo but not another, or a phase is postponed), add a **Remaining Work** section at the bottom of the spec listing what's left:

```markdown
## Remaining Work

1. **Tracker: config lookup** — Look up click tracker config from Bigtable in `/m/click` route
2. **Back-end: Redis cache** — Cache configs with invalidation on upsert/delete
```

Each item should name the **repo**, the **what**, and enough context to pick it up later.

### Rules

1. **Never document planned code as if it exists.** If a function, endpoint, or consumer isn't implemented, mark the section `PLANNED` or put it in Remaining Work.
2. **Update scope when you ship.** When planned code gets implemented, remove the `PLANNED` marker and add the repo to `Implemented in`.
3. **Cross-repo scope is per-repo.** Each repo's spec only claims implementation for code in that repo. If the tracker hasn't implemented its part yet, the back-end spec says `Implemented in: back-end` and lists tracker work under Remaining Work.
4. **Remaining Work is mandatory when work is incomplete.** If any part of a feature is unbuilt — whether in this repo or another — it MUST be in a Remaining Work section at the bottom. A spec with no Remaining Work is a claim that the feature is fully complete. Never leave a `SHIPPED` spec with known gaps undocumented.

---

## Writing a Spec

Copy `document-first-template/_templates/SPEC.md` and fill in what's relevant. For infrastructure/environment documentation, use `document-first-template/_templates/ENVIRONMENT_SPINUP.md` instead — it covers GCP/cloud services, database setup, event stores, message queues, container orchestration, CI/CD, and cross-repo sync scripts.

For complex pipeline/consumer domains with many test scenarios (e.g., a domain with a dedicated `y-scripts/` simulator and 3+ flows to verify), split testing into a separate `TESTING.md` file alongside `SPEC.md`. Use `document-first-template/_templates/TESTING.md` as the starting point. Link it from the spec's Testing section: `See [TESTING.md](TESTING.md) for full end-to-end scenarios.` For simple domains (CRUD, auth, config), the `## Testing` section inline in `SPEC.md` is sufficient.

A spec should answer the questions that matter for its domain:

- **What is it?** — One paragraph.
- **How does it work?** — Architecture, data flow, diagrams.
- **What's the schema?** — Data model (SQL tables, Bigtable families, protobuf types).
- **What are the contracts?** — API contracts (endpoints, request/response shapes).
- **What are the routes?** — Handler logic, middleware, auth.
- **What are the queues?** — RabbitMQ/BullMQ queues, consumers, message formats.
- **What can go wrong?** — Edge cases and how we handle them.
- **How do you operate it?** — Migration steps, deployment procedures, sync workflows, data pipeline processes, manual runbooks.
- **How do you test it?** — Local end-to-end testing scripts, required env vars, what to verify in each data store, expected log output.

Not every spec needs every section. A simple CRUD feature might only need schema + contracts + routes. A consumer pipeline needs different sections than an API feature. An infrastructure domain needs operational procedures. Use the template as a starting point, not a checklist.

### Spec Structure

Every spec should use these sections (include only what's relevant):

- **Overview** — One paragraph describing what it is and why it exists
- **Architecture** — Single section with ASCII flow diagrams inside a code block. Use `├──`, `└──`, `──>` to show data flow, processing pipelines, and entity hierarchies. No subsections — keep everything in one code block
- **Schema** / **Bigtable Tables** — Data model (tables, columns, constraints)
- **Contracts** — API endpoint tables (for API features)
- **Queues** — Queue consumers with message interfaces and processing steps (for pipeline features)
- **Routes** — Handler implementation details with middleware
- **Operational Procedures** — Migration steps, sync workflows, deployment processes, data pipeline procedures, manual runbooks. Document the exact commands and order of operations needed to make changes (e.g., how to add a new DB table, how to sync data between systems, how to run backfills)
- **Edge Cases** — Bullet list of everything that can go wrong and how it's handled
- **Testing** — Local end-to-end testing. Required env vars, running consumers/services, exact script commands per scenario, verification queries for PostgreSQL/Bigtable/BigQuery, expected log events. If a `y-scripts/` simulator exists, document all its modes here. For complex domains with many scenarios, split into a separate `TESTING.md` using `document-first-template/_templates/TESTING.md`. See **Testing Script Rules** below for how to build the scripts themselves
- **Files** — List of relevant source files
- **Remaining Work** — Numbered list of what's designed but not yet implemented, with repo and context

### Granularity

Be precise and granular — document exactly what each piece of code does:

- **Every endpoint**: method, path, middleware, request/response shapes, status codes, exact error messages
- **Every query**: what it reads/writes, filters, joins, ordering
- **Every consumer**: message fields, each processing step, what gets created/updated/deleted
- **Every middleware**: what it checks, what it rejects, what it attaches to the request
- **Business logic**: step-by-step what happens, including conditionals and branching
- **Validations**: field names, types, constraints, what fails and with what message
- **Operational procedures**: exact commands to run, order of operations, what to verify after each step, cross-system sync steps (e.g., DB migration → regenerate derived files → apply to downstream systems)

### Architecture Diagram Style

Two diagram types — use whichever fits (or both):

**Sequence diagrams** for multi-system communication flows:
```
System A                 System B                 System C
    |                       |                        |
    |--- Action ----------->|                        |
    |                       |-- Forward ------------>|
    |                       |<-- Response -----------|
    |<-- Result ------------|                        |
```

**Tree/arrow notation** for pipelines and data hierarchies:
```
Source System
├── QUEUE_NAME_1 ──> consumer_1
│   ├── Step 1
│   └── Forwards to NEXT_QUEUE ──> downstream pipeline
│
└── QUEUE_NAME_2 ──> consumer_2
    └── Step 1

Parent Entity (key)
├── Child Entity (key) ──── description
│   └── Grandchild Entity (key)
└── Other Child
```

---

## Using Specs with AI

Once a spec is `APPROVED`, hand it to AI for implementation:

### Start implementation
```
Read the spec at docs/{domain}/SPEC.md.
Implement Phase 1 following the exact patterns described.
Use existing codebase patterns — don't invent new ones.
```

### Continue work
```
Read the spec at docs/{domain}/SPEC.md.
We've completed Phases 1-2. Implement Phase 3 now.
The spec has all the details — follow it exactly.
```

### Review against spec
```
Compare the implementation against the spec at docs/{domain}/SPEC.md.
Flag any deviations or missing edge case handling.
```

### Update after changes
```
Read the current spec at docs/{domain}/SPEC.md.
We changed [X] in the implementation.
Update the spec to match what's in production now.
```

---

## Implementation

When implementing from an approved spec, use parallel agents aggressively to maximize speed and robustness.

> **Lifecycle pointer (methodology, not a new rule):** the discipline for *how*
> to execute this phase lives in the skills mapped under **The Development
> Lifecycle** above — `writing-plans` to shape the plan, `tdd-workflow` for
> test-first changes, `executing-plans` (drive it yourself) or
> `subagent-driven-development` (one subagent per task) to build it, then
> `requesting-code-review` → `verification-before-completion` →
> `finishing-a-development-branch` to land it. None of these change the strategy
> or rules below; they just describe how to carry them out well.

### Strategy

1. **Break the spec into independent work streams** — identify which parts can be built in parallel (e.g., schema/migrations, API contracts, route handlers, consumers, tests, config)
2. **Spawn parallel agents** — one agent per independent work stream. Each agent reads the spec and implements its assigned portion following existing codebase patterns. Maximize parallel agent spawning for speed.
3. **Sequence dependent work** — if work stream B depends on A (e.g., routes depend on contracts, consumers depend on schema), implement A first, then spawn parallel agents for everything that depends on it
4. **Verify against spec** — after all agents complete, review the full implementation against the spec to ensure nothing was missed or deviated from

### Rules

1. **Follow the spec exactly** — the spec is the source of truth. Don't add features, skip sections, or deviate from what's described
2. **Use existing codebase patterns** — read how similar features are already implemented and follow those patterns. Don't invent new abstractions
3. **Don't duplicate logic** — before writing a function, regex, constant, or utility, search the codebase for an existing one that does the same thing. If it exists, import and reuse it. If it exists but isn't exported, export it. Never copy-paste logic into a new location — single source of truth applies to code, not just specs
4. **One agent per work stream** — each agent owns a clear, non-overlapping piece of work. Avoid two agents editing the same file
5. **Update spec after implementation** — once shipped, update the spec's status to `SHIPPED` and fix any details that changed during implementation. Keep specs and code in sync

---

## Testing Script Rules

When building a `y-scripts/` simulator or test helper, follow these rules to make testing as easy as possible:

### Interactive by default

- **Run with no args → interactive mode**: prompt for each required input one at a time
- Each prompt **includes a lookup query** so the user can find valid values without leaving the terminal:
  ```
  Tip: look up a valid pk with:
    SELECT public_api_key FROM protection_script WHERE deleted_at IS NULL LIMIT 5;

  Enter pk (pk_live_...):
  ```
- All args also work **non-interactively** (pass on command line) so scripts can be automated
- **When the script has multiple flows/modes, use an arrow-key selection menu** instead of a text prompt — so the user can navigate options without typing:
  - Each option renders as `[type]  name     short description` so the category is visible at a glance
  - Use **alternate screen buffer** (`\x1B[?1049h]` / `\x1B[?1049l]`) + `readline` raw mode so the menu is isolated from terminal output
  - Call `setRawMode(true)` **before** the first render — raw mode disables `ONLCR` so `\n` stops being CR+LF; use `\r\n` everywhere in the render function
  - Clear and redraw the full screen on every keypress (`\x1B[2J\x1B[H]`) — don't try to move the cursor up N lines
  - **Lazy-import** any queue/DB libraries inside the run loop, never at the top of the file — top-level imports trigger connections and log output during the interactive menu
  - Example option shape: `{ value: "flow-key", label: "[type]  name", desc: "short description" }`

### Auto-print verification

- After each run, **print the verification SQL with actual test values filled in** — not a generic template, the real query they can copy-paste directly into a DB client:
  ```
  Verify in PostgreSQL:
    SELECT ... FROM mobile_click WHERE protection_script_id = 42 ORDER BY id DESC LIMIT 1;
  ```
- For tracker/webhook flows, **print the full URL** they can open in a browser to test via the real pipeline

### Script structure

```typescript
// 1. Parse args — if missing, prompt interactively (one at a time, each preceded by lookup tip)
// 2. Validate env vars (QUEUE names, etc.) — exit with clear message if missing
// 3. Print a summary header (mode, pk, count, etc.) before running
// 4. Run the test
// 5. Print tracker URLs / clickable links if applicable
// 6. Print the verification SQL with actual test values filled in
```

---

## Running long-lived processes (tmux)

When asked to **start / run / spin up** a long-lived process — a dev server, service, file watcher, or queue consumer — start it in a **named, detached `tmux` session**, never a foreground call or an `&`-backgrounded job. tmux outlives the assistant session, so the operator can attach and watch or interact whenever; a plain background job dies with the turn and can't be attached to. This does **not** apply to one-shot work (builds, tests, migrations, scripts) — run those inline.

### Convention

- **Session name `tapper-<repo>`** — namespace it so it never collides with the operator's other sessions. One **window per process**, named by role: `server`, `ui`, `api`, `web`, `consumer`.
- **Check it isn't already running** (`tmux has-session`) before double-starting.
- **Verify it came up** before reporting success — `curl` the port (with its own `--retry`; never a bare `sleep`) and/or `tmux capture-pane`.
- **Report the attach command** (`tmux attach -t tapper-<repo>`) + the ports.

```bash
REPO="/absolute/path/to/<repo>"          # quote it if the path has spaces
S=tapper-<repo>
tmux has-session -t "$S" 2>/dev/null && { echo "already up: tmux attach -t $S"; exit 0; }
tmux new-session -d -s "$S" -n server -c "$REPO"
tmux send-keys  -t "$S":server '<start cmd>' C-m
# add a window per extra process:
tmux new-window -t "$S" -n ui -c "$REPO"
tmux send-keys  -t "$S":ui '<start cmd>' C-m
curl --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors -sS -m3 \
  -o /dev/null -w "%{http_code}\n" http://127.0.0.1:<port>/
echo "attach: tmux attach -t $S   (Ctrl-b d detaches, Ctrl-b <n> switches windows)"
```

### Boot safety — never boot a prod-pointed repo

Some repos' local `.env` points at **production** (Slack, message queues, the prod database). Booting those locally isn't a harmless dev server — it re-posts or re-injects **real** data. **Do not start them**; run the repo's safe gate instead (compile / typecheck / tests). The per-repo start commands, ports, and the exact never-boot list live in the tapper **`dev-up`** skill — check it before starting anything.

---

## Cross-repo References

When a feature spans multiple repos, each repo owns its own specs. Don't duplicate — **reference**.

### Detecting the GitHub URL

Run `git remote get-url origin` to extract the GitHub org and repo name. Use this for all cross-repo links — never hardcode.

### Convention

Add a cross-repo header at the top of the spec, below the status block:

```markdown
> **Cross-repo:** {Brief description of what lives in the other repo.}
> - **{Repo name}:** `{repo}: docs/{path}/SPEC.md` — {what it covers}
```

Or for a spec that has a direct counterpart:

```markdown
> **{Repo name} counterpart:** `{repo}: docs/{path}/SPEC.md` — {what the counterpart covers}
```

### Clickable links

**All doc references must be clickable markdown links** — both intra-repo and cross-repo.

**Intra-repo** (relative to current file):
```markdown
> **Parent:** [mobile-app-protection](../SPEC.md)

| [mobile-click-trackers](mobile-click-trackers/SPEC.md) | Click tracker CRUD |
```

**Cross-repo** (GitHub URLs with both `master` and `dev` links):
```markdown
> **Tracker counterpart:** [master](https://github.com/{org}/{repo}/blob/master/docs/.../SPEC.md) | [dev](https://github.com/{org}/{repo}/blob/dev/docs/.../SPEC.md) — description

See tracker: SPEC.md — [master](https://github.com/{org}/{repo}/blob/master/docs/.../SPEC.md) | [dev](https://github.com/{org}/{repo}/blob/dev/docs/.../SPEC.md)
```

Cross-repo links use absolute GitHub URLs with **both `master` and `dev` branches** so the link works regardless of which branch you're viewing. Format: `[master](url) | [dev](url)`.

Detect the GitHub org from `git remote get-url origin` — never hardcode org or repo names in links.

### Rules

1. **Each repo owns its own content.** Don't duplicate specs across repos.
2. **Don't duplicate.** If something is defined in one repo's spec, the other repo references it.
3. **Overview specs link to all sub-specs.** When a feature is split across repos, the overview spec in each repo links to all sub-specs in both repos.
4. **Keep references up to date.** When a spec moves or is renamed, update references in the other repo.
5. **All references must be clickable.** Use markdown link syntax `[text](path)` for every doc reference — never plain text paths.

---

## Rules

1. **No code without a spec.** If it's worth building, it's worth describing first.
2. **Spec matches production.** When code changes, the spec updates. No drift.
3. **Spec reflects implementation scope.** Mark what's implemented (and where) vs what's planned. Never describe planned code as if it exists.
4. **Follow existing patterns.** The spec references how the codebase already works, not how it could work.
5. **Edge cases aren't optional.** If you can't list what goes wrong, you don't understand it yet.
6. **Specs live in git.** Same PR, same branch, same review.
7. **Cross-repo features reference, don't duplicate.** Each repo owns its specs. Link to the other repo's specs when functionality spans repos.
8. **Improve the template when you improve the process.** If you update a rule, add a section, or fix something in this file or `_templates/`, commit and push that change to the `document-first-template` submodule repo so all repos pulling the submodule get the improvement. Don't let template improvements rot in one repo's local copy.

---

## Quick Start

```bash
# 1. Create a domain folder
mkdir docs/my-domain

# 2. Copy the template
cp document-first-template/_templates/SPEC.md docs/my-domain/SPEC.md

# 3. Write the spec (fill in relevant sections)

# 4. Add to docs/README.md index

# 5. Review — walk through with team / AI

# 6. Implement — phase by phase

# 7. Update status: DRAFT → APPROVED → IN PROGRESS → SHIPPED
```

---

*Document first. Ship with confidence.*
