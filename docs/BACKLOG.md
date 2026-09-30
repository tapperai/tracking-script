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

- **The tag never starts the monitor (issue #3).** GTM matches the
  `access_globals` key exactly and `callInWindow('tapper.init', pk)` needs
  execute on `tapper.init`; `main` grants `tapper` and the Gallery-served
  `551ea056` grants nothing. Fix pending on branch
  `fix/gtm-template-grant-tapper-init`: grant `tapper.init`, check full paths
  in `validate_template.py`, add the fixed commit as the first
  `metadata.yaml` entry. Done when the Gallery listing
  (`versions[0].sha`) serves it and a GTM Preview shows `tapper.init` called.

---

## P0 — needs verification

(Implemented somewhere in the build but the user hasn't manually seen it work.
Walk through each one before claiming done.)

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
