# Backlog

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
