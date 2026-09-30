# Tracking Script — GTM Community Template

> **Status:** `SHIPPED`
>
> **Created:** 2026-08-26
> **Last updated:** 2026-10-01
>
> **Implemented in:** tracking-script

## Overview

`tracking-script` is a single-file Google Tag Manager (GTM) Community
Template (`template.tpl`) that injects Tapper's client-side monitoring
bundle and initializes it with the customer's Public Key. A customer imports
the template into their GTM workspace, creates a tag from it with their
`pk_live_...` / `pk_test_...` key, sets the trigger to All Pages, and
publishes — at that point every page view on their site loads
`https://monitor.tapper.ai/bundle.js` and calls `tapper.init(pk)`, which is
how Tapper starts detecting invalid traffic for that customer's ad
campaigns. There is no server, build step, or runtime of its own in this
repo — the whole product surface is the one `.tpl` file plus the CI gate
that validates it.

---

## Architecture

```
Customer's GTM workspace
    |
    |-- imports template.tpl from the Community Template Gallery, which
    |   serves the commit named by the FIRST sha in metadata.yaml's
    |   versions list (not main HEAD)
    |
    |-- creates a TAG from the template, sets Public Key + "All Pages" trigger
    |
    v
Page load in customer's site
    |
    |-- GTM sandboxed JS (___SANDBOXED_JS_FOR_WEB_TEMPLATE___) runs:
    |     1. pk = data.pk (from the tag's Public Key field)
    |     2. if no pk -> logToConsole + gtmOnFailure()
    |     3. else injectScript('https://monitor.tapper.ai/bundle.js', ...)
    |
    v
monitor.tapper.ai/bundle.js loads in the page
    |
    |-- on injectScript success -> callInWindow('tapper.init', pk)
    |-- on injectScript failure -> logToConsole + gtmOnFailure()
```

The GTM Community Template Gallery reads `metadata.yaml` on this repo's
default branch (`main`) and serves the `template.tpl` of the commit named by
the FIRST `sha` in its `versions` list, not `main` HEAD. Google picks up a new
first entry in typically 2-3 days. There is no separate build/deploy job: the
release is a merge that adds a new first `versions` entry, and a merge that
changes `template.tpl` without one reaches no customer. Imported templates
never auto-update; each GTM container that imported the template has to
accept the update and publish. `.github/workflows/validate.yml` gates every
push and PR against `main` with `scripts/validate_template.py`.

---

## Schema

Not applicable — this repo has no database. The only "schema" is the
`.tpl` file's own sectioned format (`___INFO___`, `___TEMPLATE_PARAMETERS___`,
`___SANDBOXED_JS_FOR_WEB_TEMPLATE___`, `___WEB_PERMISSIONS___`, `___TESTS___`,
`___NOTES___`), each a JSON or plain-text block delimited by the
`___SECTION_NAME___` markers GTM's template format requires.

### Template Parameters (`___TEMPLATE_PARAMETERS___`)

| Name | Type | Validation |
|---|---|---|
| `pk` | TEXT ("Public Key") | `NON_EMPTY`; regex `^pk_(live\|test)_[A-Za-z0-9]+$` |

### Web Permissions granted (`___WEB_PERMISSIONS___`)

| Permission | Grant |
|---|---|
| `logging` | `environments: debug` |
| `access_globals` | key `tapper.init`, read=false, write=false, execute=true |
| `inject_script` | urls: `https://monitor.tapper.ai/bundle.js` |

These three grants are exactly what the sandboxed JS needs and nothing more,
and `scripts/validate_template.py` enforces both directions in CI:

- **Nothing missing:** CI fails if the sandboxed JS uses an API without its
  matching grant (the "empty access_globals" class of bug).
- **Nothing extra:** CI fails if an `access_globals` key or operation is
  granted that the JS never uses with that operation, if an `inject_script`
  URL differs from the literal script URL in the JS or contains a wildcard,
  if `logging` is enabled beyond `debug`, or if any permission is granted
  that no `require()`d API needs. A merge to `main` is a Gallery release into
  every installer's site, so a widened grant must turn CI red. Comments are
  stripped from the sandboxed JS before these scans, so a commented-out call
  can neither satisfy nor widen a grant.

**The `access_globals` key is the FULL dotted path, matched exactly.**
GTM's runtime checker (read from a live `gtm.js`) is
`executeKeys.indexOf(path) > -1`, and `callInWindow('tapper.init', pk)`
asserts `execute` on `'tapper.init'`; a failed check throws
`Prohibited execute on global variable: tapper.init.`. A grant on `tapper`
does not cover it. History: the Gallery version `551ea056` granted no
`access_globals` key, and `e3c043f` granted `tapper`; neither could call
`tapper.init`, so no earlier version of this template initialised the
monitor. Fixed by granting `tapper.init` (issue #3). Which receiver
`callInWindow` binds does not matter: the bundle defines `Tapper.init` as an
arrow-function class field, so its `this` is fixed by the language.

---

## Contracts

Not applicable — no HTTP API is exposed by this repo. The only external
contract is the one URL the template is permitted to inject:
`https://monitor.tapper.ai/bundle.js` (owned/deployed by a different
service, not this repo), and the global `tapper.init(pk)` function that
bundle is expected to expose on `window`.

---

## Routes

Not applicable — no server.

---

## Queues

Not applicable — no message broker.

---

## Operational Procedures

### Releasing a template change

1. Edit `template.tpl` directly (it is hand-authored, not generated — GTM's
   own editor UI can export a `.tpl` too, in which case reconcile the export
   back into this file rather than replacing it wholesale, since this file
   also carries the CI-relevant sections).
2. Leave `___INFO___.version` at `1`: it is GTM's export-format version, not
   a release counter (Google's own gallery templates all carry `1`).
3. On the SAME branch, in a SECOND commit, add the template commit's full SHA
   as the FIRST entry of `metadata.yaml`'s `versions:` list with change notes,
   keeping every earlier entry below it. The Gallery serves only the first
   entry, so a template change that never reaches `metadata.yaml` never
   reaches customers. CI enforces it: `validate_template.py --metadata
   metadata.yaml` fails unless the served sha is an ancestor of HEAD and
   carries a byte-identical `template.tpl`.
4. Open a PR to `main`. `.github/workflows/validate.yml` runs on push and
   PR against `main`:
   - `python3 scripts/validate_template.py template.tpl --metadata
     metadata.yaml` fails the check if any `___..._` JSON section doesn't
     parse, if the sandboxed JS calls a `require()`'d API (`injectScript`,
     `callInWindow`, `copyFromWindow`, `setInWindow`, `createQueue`,
     `aliasInWindow`, `logToConsole`) whose matching permission isn't granted
     (full dotted path for window access), if any grant is wider than what
     the JS uses (the least-privilege checks), or if the first
     `metadata.yaml` sha does not carry this `template.tpl`.
   - `node scripts/run_template_tests.mjs template.tpl` runs the
     `___TESTS___` scenarios with GTM's exact-path permission semantics.
5. Merge to `main` with a **merge commit** (squash and rebase are disabled
   on this repo; both would rewrite the SHA that `metadata.yaml` names, and
   the post-merge CI run would go red). The Community Template Gallery reads
   `metadata.yaml` on the default branch, so the merge **is** the release;
   Google documents pickup as typically 2-3 days. There is no separate deploy
   step to run.
6. Customers do NOT get the new version automatically. GTM shows an
   "update available" notice on the template in each workspace that imported
   it from the Gallery; someone with edit access must accept it, review any
   permission change, then publish the container.

---

## Edge Cases

- **Missing/empty Public Key**: the sandboxed JS checks `if (!pk)` before
  doing anything else — logs `'Tapper public key is missing'` via
  `logToConsole` and calls `data.gtmOnFailure()`. GTM's own
  `NON_EMPTY` + regex parameter validators should catch this at tag-config
  time already, but the runtime check is a second line of defense.
- **Bundle fails to load** (network error, `monitor.tapper.ai` down, etc.):
  `injectScript`'s failure callback logs `'Failed to load Tapper script'`
  and calls `data.gtmOnFailure()` — the tag reports failure to GTM but does
  not throw, so it can't break the rest of the customer's tag sequence.
- **Wrong-shaped Public Key** (doesn't match `pk_live_...` / `pk_test_...`):
  rejected by the `REGEX` `valueValidators` on the `pk` parameter before the
  tag can even be saved in GTM — never reaches the sandboxed JS.

---

## Testing

See [`TESTING.md`](TESTING.md).

---

## Files

- `template.tpl` -- the entire GTM Community Template: metadata, the `pk`
  parameter, the sandboxed JS that injects the bundle and calls
  `tapper.init`, the web permissions grant, and a built-in GTM test scenario.
- `metadata.yaml` -- gallery listing metadata (homepage, docs URL) + the
  `versions` ledger the Community Template Gallery reads to know which
  commit SHA corresponds to which released version.
- `scripts/validate_template.py` -- stdlib-only pre-deploy gate: parses each
  JSON section of `template.tpl`, checks every `require()`'d API used in the
  sandboxed JS has its permission granted in `___WEB_PERMISSIONS___`, checks
  every window path is granted exactly (full dotted path + operation) and
  nothing beyond what the JS uses, checks Gallery categories, and with
  `--metadata` checks the Gallery-served sha.
- `scripts/run_template_tests.mjs` -- dependency-free Node runner for the
  `___TESTS___` scenarios with GTM's exact-path permission semantics (GTM
  itself only runs them inside its web editor).
- `.github/workflows/validate.yml` -- runs `validate_template.py --metadata`
  and `run_template_tests.mjs` on every push/PR to `main`, since
  merge-to-main is the actual release for this repo.
- `README.md` -- customer-facing setup instructions (import → create tag →
  enter Public Key → trigger → publish).

---

## Remaining Work

- Run the four `___TESTS___` scenarios in GTM's own editor and one GTM
  Preview on a test site with the fixed template (the local runner emulates
  GTM; it is not GTM): `tapper.init` called and the tag status `Succeeded`.
- Confirm the Gallery listing serves the new sha (Google: typically 2-3 days
  after `metadata.yaml` lands on `main`).
