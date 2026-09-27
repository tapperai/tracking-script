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

- **Gallery template never initialised the monitor (TRACK-01, 2026-09-28).**
  Every served version denied `callInWindow('tapper.init')`: `551ea056` had an
  empty `access_globals`, `e3c043f` granted `tapper` (GTM matches the full
  dotted path), and `e3c043f` never reached `metadata.yaml` anyway. Fixed by
  granting `tapper.init`, adding Gallery categories, exact-path validation,
  a local `___TESTS___` runner, and a CI check that the Gallery-served sha
  carries the current template. Needs: (1) the GTM editor **Tests** tab run on
  the new template; (2) a GTM Preview on a test site showing `tapper.init`
  called AND the tag status `Succeeded` (`tapper.init` is async and returns a
  Promise; if GTM's conversion of that return value threw, the monitor would
  still start but `gtmOnSuccess` would never be reached); (3) the Gallery listing showing the new version (Google: 2-3 days).
  Blast radius measured 2026-09-28: 0 of the live clients' public GTM
  containers install via this template (all use a Custom HTML tag), so no
  client needs to update today.

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
