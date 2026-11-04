# tracking-script

Single-file GTM Community Template (`template.tpl`): injects `https://monitor.tapper.ai/bundle.js` and calls `tapper.init(pk)`, with `access_globals` execute granted on the exact key `tapper.init`. No build, no package.json.

**PUBLIC repo.** No customer names, counts, rates, domains, internal table or dataset names, or quotes from people in any commit, PR, issue, comment or doc. Technical change only; the why and evidence go in a private repo. GitHub keeps every earlier revision of a PR or comment body, so get it right the first time. Never put an internal hostname, project id or instance name in a file, commit message, PR or issue. `scripts/leak-guard/` (a byte-identical copy of the design-system canon) runs over the checkout in the required validation job with `--redact`.

## Release
No deploy job. The GTM Gallery serves the `template.tpl` of the commit named by the FIRST `sha` in `metadata.yaml` on `main`, not HEAD (a new first entry is picked up in typically 2-3 days). A merge that changes `template.tpl` reaches no customer until that sha is the first entry, and GTM never auto-updates an imported template: each container accepts the update in a workspace and publishes. Merges are MERGE commits (`gh pr merge <n> --merge`; squash and rebase are off) so the named sha survives. How to see what the Gallery serves now: `docs/ENVIRONMENT_SPINUP.md`.

## Tests
Local command: `node scripts/test-changed.mjs` (`-- --list`, `-- --base <ref>`): validates the template and runs its tests, prints the `Tests: local (...)` trailer. CI runs the same validation on every ready PR (`Validate template.tpl (pre-deploy gate)`, about 10 s); the ruleset on `main` is disabled, so never merge on red. Detail: `docs/ENVIRONMENT_SPINUP.md`.

## Fleet rules (full text: umbrella `CLAUDE.md`)
PRs target `main`; no dev branch, nothing promotes. Identity, review gate, approval gate and the config standard come from the umbrella file. Testing: record `Tests: local (<cmd>)` or `Tests: skip (<reason>)` as the last paragraph of the commit AND the PR description.

## Customer copy
Copy SELLS: confident and plain; no "not available / planned / next / yet" disclaimers, no internals. One sales-wide platform list: Google, Meta, TikTok, Microsoft/Bing, LinkedIn, Snapchat, Apple.

## Docs
Skill `docs-rule`. Pages (old layout): `docs/tracking-script/SPEC.md` (template, permissions, release), `docs/TESTING.md` (validator, `___TESTS___`, manual GTM Preview check), `docs/ENVIRONMENT_SPINUP.md` (CI and Gallery mechanics). New choices go in `docs/decisions/NNNN-title.md`. `docs/BACKLOG.md` is the living list of asks: capture a new ask BEFORE starting; when it ships move it under `## Done` with a one-line note and date; unverified code goes under `## P0 - needs verification`.
