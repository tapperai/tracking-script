# tracking-script — GTM Community Template (Tapper monitoring tag)

## PUSH / DEPLOY GUARD
**Pushing to `main` IS the deploy.** The GTM Community Template Gallery reads
this repo's default branch (`main`) + `metadata.yaml` directly on push — there
is no build/publish step of our own. So NEVER `git push`, merge to `main`, or
`gh pr merge` without EXPLICIT, per-branch approval. Local commits on a feature
branch (e.g. `tracking-script/flawless-fixes`) are fine.

## What this is
A single **Google Tag Manager custom template** (`template.tpl`) named "Tapper -
Monitoring Script". Merchants import it from the GTM Community Template Gallery,
enter their Tapper Public Key (`pk_live_...` / `pk_test_...`), set an All-Pages
trigger, and publish. At runtime the tag injects `https://monitor.tapper.ai/bundle.js`
and calls `window.tapper.init(pk)`. That bundle (built elsewhere) feeds the
tracker ingestion pipeline. This repo owns ONLY the GTM template wrapper — not
the monitoring bundle. Tiny repo: essentially one `.tpl` file + a CI validator.

## Stack
- **GTM custom-template DSL** — a single `template.tpl` with `___SECTION___`
  delimited blocks: `INFO`, `TEMPLATE_PARAMETERS`, `SANDBOXED_JS_FOR_WEB_TEMPLATE`,
  `WEB_PERMISSIONS`, `TESTS`, `NOTES`. Sandboxed JS is GTM's restricted subset
  (no free DOM/`window`; only `require()`'d APIs).
- **Validator:** `scripts/validate_template.py` — pure Python 3 stdlib, no npm,
  no network, no secrets.
- No `package.json`, no node build. `metadata.yaml` carries the version/sha +
  changeNotes the Gallery displays.

## THE GATE COMMAND
```
python3 scripts/validate_template.py template.tpl   # must exit 0
```
Run it after ANY edit to `template.tpl`. It is exactly the CI gate
(`.github/workflows/validate.yml`, on push + PR to `main`). It checks: (1) every
JSON section parses; (2) every window path in `callInWindow`/`copyFromWindow`/
`setInWindow`/`createQueue`/`aliasInWindow` has its ROOT identifier granted in
`access_globals`; (3) every `require()`'d API has its matching permission
granted (`injectScript`→`inject_script`, `callInWindow`→`access_globals`,
`logToConsole`→`logging`). Never mask its exit code.

## Where things live / how to change the tag
- **Runtime logic:** `___SANDBOXED_JS_FOR_WEB_TEMPLATE___` in `template.tpl`.
- **Add a config field the merchant fills in:** `___TEMPLATE_PARAMETERS___`
  (its `key` becomes `data.<key>` in the JS; today only `pk`).
- **Grant a new capability:** you MUST edit `___WEB_PERMISSIONS___` in the same
  change (see footguns). Currently granted: `logging` (debug env only),
  `access_globals` (global `tapper`, execute-only), `inject_script`
  (allowlisted URL `https://monitor.tapper.ai/bundle.js`).
- **Ship a new template version:** bump the `sha` + `changeNotes` in
  `metadata.yaml` (the Gallery reads this).

## Conventions to match
- Success/failure MUST route through `data.gtmOnSuccess()` / `data.gtmOnFailure()`
  — never leave a branch that calls neither.
- Guard missing input before injecting: `if (!pk) { logToConsole(...); data.gtmOnFailure(); }`.
- Only ever call `window.tapper.*` (that's the sole granted global). Any other
  global needs a new `access_globals` grant.
- Keep a matching scenario in `___TESTS___` (GTM's `runCode`/`assertApi` DSL).

## Footguns
- **A `require()` without its permission = runtime init breaks.** The
  empty-`access_globals` class of bug is exactly what the validator catches —
  add the grant in `___WEB_PERMISSIONS___` in the same commit as the JS change.
- **`inject_script` is URL-allowlisted.** Changing `scriptUrl` in the JS
  requires updating the `urls` list in the `inject_script` permission or the
  script silently won't load.
- **`access_globals` grant is execute-only** for `tapper` (read/write=false,
  execute=true). Don't loosen it without reason.
- **`template.tpl` starts with a UTF-8 BOM** (before `___TERMS_OF_SERVICE___`).
  Preserve it — don't strip it in an editor.
- Sandboxed JS is NOT real JS: no arrow-function-free rules aside, you can only
  use GTM sandbox APIs (`injectScript`, `callInWindow`, `logToConsole`, etc.).
  Regular DOM/`window`/`fetch` are unavailable.

## What NOT to do
- Don't add a node/npm toolchain — the gate is intentionally pure-stdlib Python
  so CI can never fail for a credential/flaky reason.
- Don't merge to `main` unprompted (that's the live publish — see guard).
- Don't edit the monitoring bundle here; it isn't in this repo.
