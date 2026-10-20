# Backlog

- 2026-10-18: testing policy, skip path proven by this docs-only change (devops-sre).

Living list of every TODO the user has called out. When the user mentions
something new, capture it here verbatim before starting work. When something
lands, move it under "Done" with the SHA / date.

Categories:

- **P0 — open**: explicitly asked, not shipped yet.
- **P0 — needs verification**: code says done but never end-to-end checked
  with the user; treat as suspect until verified.
- **P1 — open**: asked-for but lower urgency, or feature-parity items the
  user wants but hasn't blocked on.
- **P2 — open**: nice-to-have, future parity, deferred.
- **Done**: shipped + verified.

---

## P0 — open

(Explicitly asked, not shipped yet. Add new items here as the user mentions
them. Each item should have enough context to pick up cold.)

---

## P0 — needs verification

- **2026-10-17: CI standard (no test gate on merges) live.** `tests.yml` holds the test set (mode `CI_GATE_MODE`), `test-batch.yml` runs it every 10 merges, nightly and on demand and bisects a red batch. Ruleset `required-checks` (id 25124315) names `CI gate` and the pre-deploy check but is DISABLED (read 2026-10-20), so neither is required on `main`; decide whether it should be enforced. The batch and nightly runs on `main` were green on 2026-10-19 and 2026-10-20.

(Implemented somewhere in the build but the user hasn't manually seen it work.
Walk through each one before claiming done.)

- **The tag never started the monitor (issue #3; fixed, merged to `main`
  2026-09-30 in PR #7, awaiting Gallery pickup).** No earlier version could call
  `callInWindow('tapper.init', pk)`: `551ea056` granted no `access_globals`
  key and `e3c043f` granted `tapper`, which does not cover `tapper.init`
  because GTM matches the full dotted path exactly. Fixed by granting execute
  on `tapper.init` and listing the fixed commit as the first `metadata.yaml`
  entry, with Gallery categories, exact-path and least-privilege checks in
  `validate_template.py`, a local `___TESTS___` runner, and a CI check that
  the Gallery-served sha carries the current template. Needs: (1) the GTM
  editor **Tests** tab run on the new template; (2) a GTM Preview on a test
  site showing `tapper.init` called AND the tag status `Succeeded`
  (`tapper.init` is async and returns a Promise; if GTM's conversion of that
  return value threw, the monitor would still start but `gtmOnSuccess` would
  never be reached); (3) the Gallery listing showing the new version
  (Google: typically 2-3 days).

  Post-merge checks (PR #7 merged 2026-09-30, Gallery-served sha
  `295cc787192dcc3bcf2b237b2febebe62a0711a1`, the first `metadata.yaml`
  entry):
  - **By 2026-10-03:** open the template in the Community Template Gallery
    and confirm the listed version is `295cc787`, the permissions show
    `tapper.init` under "Accesses global variables" with execute, and the
    change notes match `metadata.yaml`. If it still shows `551ea056` after
    2026-10-05, check the Gallery's import status for the repository.
  - **A person runs, after the Gallery shows the new version:**
    1. In a GTM container, import or update the template, open the template
       editor, and run the **Tests** tab: all four scenarios pass.
    2. On a test site, add the Tapper tag with a test publishable key, start
       GTM **Preview**, load a page, and confirm the tag status is
       `Succeeded`, `bundle.js` loads from `monitor.tapper.ai`, and
       `tapper.init` is called once with the key.
  Move this item to Done only when all three hold.

  **Read 2026-10-20:** the Gallery JSON lists `295cc787` first but with
  `updateError: 5`, and the served `access_globals` permission still has no
  key, so the Gallery never imported the fix; (3) does not hold and (1) and
  (2) cannot start. Next: check the import status in the Gallery and fix what
  it rejects.

---

## P1 — open

(Asked-for but lower urgency, or feature-parity items the user wants but
hasn't blocked on.)

---

## P2 — open

(Nice-to-have, future parity, deferred. Each gets its own spec when
prioritized.)

---

## Meta / hygiene

- Keep this file fresh: each new explicit user ask gets an entry **before** I
  start coding it. After it ships and the user confirms, move it under Done.
- Never silently drop an item — if I push back on scope, note the rationale
  inline.

---

## Done

(items move here with a one-line note + commit SHA / date once shipped + verified)

- 2026-10-18: testing policy, affected path proven by this docs-only change (devops-sre).
