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
| `access_globals` | key `tapper`, read=false, write=false, execute=true |
| `inject_script` | urls: `https://monitor.tapper.ai/bundle.js` |

**Known defect (issue #3): the `access_globals` grant does not match what
the sandboxed JS needs, so the tag never starts the monitor.** GTM's
`access_globals` checker matches the granted key exactly (`indexOf` on the
granted key list; a failed check throws `Prohibited execute on global
variable: <key>.`), and `callInWindow('tapper.init', pk)` needs execute on
`tapper.init`. The grant on `main` is on `tapper`, which does not cover it,
and the version the Gallery serves (`551ea056`) grants no `access_globals`
key at all. `scripts/validate_template.py` does not catch this: it checks
only the ROOT identifier of each window path (`tapper`). The fix (grant
`tapper.init`, check the full path in CI, add a new first `metadata.yaml`
entry) is pending on branch `fix/gtm-template-grant-tapper-init`; this
section is rewritten when it lands.

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
3. In a second commit on the same branch, add the template commit's full SHA
   as the FIRST entry of `metadata.yaml`'s `versions:` list with change
   notes, keeping every earlier entry below it. The Gallery serves only the
   first entry, so a template change that never reaches `metadata.yaml`
   never reaches customers.
4. Open a PR to `main` — `.github/workflows/validate.yml` runs
   `scripts/validate_template.py template.tpl` on push and PR against `main`
   and fails the check if any `___..._` JSON section doesn't parse, or if
   the sandboxed JS calls a `require()`'d API (`injectScript`,
   `callInWindow`, `copyFromWindow`, `setInWindow`, `createQueue`,
   `aliasInWindow`, `logToConsole`) whose matching permission isn't granted
   in `___WEB_PERMISSIONS___`.
5. Merge to `main` with a merge commit (squash and rebase are disabled on
   this repo; both would rewrite the SHA that `metadata.yaml` names). The
   merge is the release only because it moves the first `metadata.yaml`
   entry; the Gallery picks it up in typically 2-3 days. There is no separate
   deploy step to run.
6. Customers do not get the new version automatically: each GTM workspace
   that imported the template shows an update notice, and someone with edit
   access must accept it, review any permission change and publish.

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
  push/PR to `main`, so no template change reaches `main` (where
  `metadata.yaml` can name it for the Gallery) without passing it.
- `README.md` -- customer-facing setup instructions (import → create tag →
  enter Public Key → trigger → publish).

---

## Remaining Work

- Fix the `access_globals` grant (issue #3, see Web Permissions above): grant
  execute on `tapper.init`, make `validate_template.py` check the full dotted
  path, add the fixed commit as the first `metadata.yaml` entry, then confirm
  the Gallery listing serves it and run one GTM Preview on a test site.
