## Document First Development

**Every new feature or significant change must have a spec in `docs/` before implementation begins.** Skip steps 1-5 only if the user explicitly asks to write code directly (e.g., "just fix this", "skip the spec").

1. **Before implementing any feature or significant change**, pull the latest template:
   - Run `git submodule update --remote document-first-template`
   - Read `document-first-template/DOCUMENT_FIRST.md` for spec rules, structure, and conventions
   - Run `git diff document-first-template` — if there is output, the template has new changes: read `document-first-template/PROMPT.md` and execute Phase 1 (sync infrastructure) + Phase 3 (enforce updated rules on all existing specs) before continuing
2. Before writing code, check if a spec exists at `docs/{domain}/SPEC.md`
3. If no spec exists, create one from `document-first-template/_templates/SPEC.md` first
4. **After writing the spec, open the file and STOP — wait for user confirmation before implementing**
5. Once confirmed, implement from the spec — follow it exactly. Break the spec into independent work streams and **spawn parallel agents** (one per work stream) to maximize speed. Sequence dependent work — implement dependencies first, then parallelize everything that follows
6. After implementing, update the spec to match what was built — keep specs and code in sync at all times. Mark `Implemented in:` with the current repo name. Move completed items out of Remaining Work. Mark any sections that are designed but not yet coded as `PLANNED`
7. **For doc commands** (e.g., `Check spec drift`, full rerun, setup) — first run `git submodule update --remote document-first-template`, then read `document-first-template/PROMPT.md` and follow its instructions

## Backlog Discipline

`docs/BACKLOG.md` is the single living list of every TODO the user has called out, **including ones that have already been shipped**.

- When the user asks for something new, capture it in `docs/BACKLOG.md` *before* starting work — under the right priority (`P0` / `P1` / `P2`).
- When something ships, **don't delete it** — move it under `## Done` with a one-line note + the date so we can audit what landed and when.
- Items that exist as code but the user has not yet seen working live in `## P0 — needs verification`.
- Never silently drop a request. If you push back on scope, write the rationale inline next to the entry.
- Treat `docs/BACKLOG.md` as authoritative when the user says "did you do X" — search there first before re-reading code or git log.
