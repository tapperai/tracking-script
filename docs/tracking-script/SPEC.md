# Tracking Script — GTM Community Template

> **Status:** `SHIPPED`
>
> **Created:** 2026-08-26
> **Last updated:** 2026-08-26
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
    |-- imports template.tpl (Community Template Gallery, reads default
    |   branch of this repo directly via metadata.yaml)
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

The GTM Community Template Gallery deploys by reading `metadata.yaml` +
`template.tpl` directly off this repo's default branch (`main`) — there is
no separate build/deploy job. A push to `main` is effectively the deploy, so
`.github/workflows/validate.yml` gates every push and PR against `main` with
`scripts/validate_template.py` before Google can pick up a bad template.

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
| `access_globals` | key `tapper`, read=false, write=false, execute=true |
| `inject_script` | urls: `https://monitor.tapper.ai/bundle.js` |

These three grants are exactly what the sandboxed JS needs and nothing more
(see `scripts/validate_template.py`, which fails CI if the sandboxed JS uses
an API without its matching grant — this is the "empty access_globals" class
of bug the validator was written to catch).

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
2. Bump `___INFO___.version` if the parameter/permission shape changed.
3. Add a new entry to `metadata.yaml`'s `versions:` list with the commit SHA
   and change notes once the commit lands (see `35b815f` for the pattern —
   metadata.yaml's `sha` tracks the GTM-exported template commit).
4. Open a PR to `main` — `.github/workflows/validate.yml` runs
   `scripts/validate_template.py template.tpl` on push and PR against `main`
   and fails the check if any `___..._` JSON section doesn't parse, or if
   the sandboxed JS calls a `require()`'d API (`injectScript`,
   `callInWindow`, `copyFromWindow`, `setInWindow`, `createQueue`,
   `aliasInWindow`, `logToConsole`) whose matching permission isn't granted
   in `___WEB_PERMISSIONS___`.
5. Merge to `main` — the Community Template Gallery reads `main` +
   `metadata.yaml` directly, so the merge **is** the deploy. There is no
   separate deploy step to run.

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
  JSON section of `template.tpl` and checks every `require()`'d API used in
  the sandboxed JS has its permission granted in `___WEB_PERMISSIONS___`.
- `.github/workflows/validate.yml` -- runs `validate_template.py` on every
  push/PR to `main`, since merge-to-main is the actual deploy for this repo.
- `README.md` -- customer-facing setup instructions (import → create tag →
  enter Public Key → trigger → publish).

---

*No Remaining Work at time of writing — the template, its permission grants,
and the CI validation gate are all shipped and live.*
