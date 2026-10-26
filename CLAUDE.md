# tracking-script

Single-file GTM Community Template (`template.tpl`): injects `https://monitor.tapper.ai/bundle.js` and calls `tapper.init(pk)`, with `access_globals` execute granted on the exact key `tapper.init`. No build, no package.json.

**PUBLIC repo.** No customer names, counts, rates, domains, internal table or dataset names, or quotes from people in any commit, PR, issue, comment or doc. Technical change only; the why and evidence go in a private repo. GitHub keeps every earlier revision of a PR or comment body, so get it right the first time.

## Release
No deploy job. The GTM Gallery serves the `template.tpl` of the commit named by the FIRST `sha` in `metadata.yaml` on `main`, not HEAD, and picks up a new first entry in typically 2-3 days. A merge that changes `template.tpl` reaches no customer until that sha is the first entry. GTM never auto-updates an imported template: each container accepts the update in a workspace and publishes. Merges are MERGE commits (`gh pr merge <n> --merge`; squash and rebase are off) so the named sha survives.

To see what the Gallery serves now, read `versions[0].sha` and `permission` from https://tagmanager.google.com/api/gallery/owners/tapperai/templates/tracking-script (drop its first line). Check `docs/BACKLOG.md` (P0 needs verification) for whether the `tapper.init` permission fix has reached the Gallery.

## Tests
- Local command: `node scripts/test-changed.mjs` (`-- --list`, `-- --base <ref>`). It runs `python3 scripts/validate_template.py template.tpl --metadata metadata.yaml` (needs full git history) and `node scripts/run_template_tests.mjs template.tpl` unless the change is prose only, and prints the `Tests: local (...)` trailer.
- CI: `.github/workflows/tests.yml`, job `Validate template.tpl (pre-deploy gate)` (about 10 s) on every ready PR next to `CI gate` (mode from `CI_GATE_MODE`); `test-batch.yml` batches and bisects; `ci-label.yml` maps the `ci:` labels. The ruleset on `main` is disabled, so a red check does not lock the button: never merge on red.

## Fleet rules (full text: root `CLAUDE.md` of the tapper folder)
- **Branch flow:** PRs target `main`; no dev branch, nothing promotes.
- **Identity:** work from the operator's laptop is his own GitHub login (plain `git`/`gh`); work on Loop's machine is `tapper-loop[bot]`.
- **Review gate:** one reviewer for a RISKY migration, enforcement/blocking, money or a customer-visible number (plus security-reviewer for auth, secrets, cookies, PII); verdict published on the PR as `VERDICT #n @ <sha>: APPROVE`. Everything else merges on the author's own verification.
- **Testing policy:** per change choose local, affected or none and record it: `Tests: local (<cmd>)`, `Tests: affected`, or `Tests: skip (<reason>)`, as the last paragraph of the commit AND the PR description. Local command: `node scripts/test-changed.mjs`.
- **Immediate first, sweep as backstop:** a state change updates every copy in the same code path; a sweep only cleans up what tripped.
- **Config standard:** business limits are a typed code default overridden by a DB settings row (audit, reset); customer/partner secrets are KMS-sealed in the service's own DB, never Secret Manager, never plaintext.

## Customer copy
Copy SELLS: confident and plain; no "not available / planned / next / yet" disclaimers and no internals. One sales-wide platform list: Google, Meta, TikTok, Microsoft/Bing, LinkedIn, Snapchat, Apple.

## Docs
Rule: skill `docs-rule`. This repo's pages are still in the old layout: `docs/tracking-script/SPEC.md` (template, permissions, release), `TESTING.md` (validator, `___TESTS___`, manual GTM Preview check), `ENVIRONMENT_SPINUP.md` (CI and Gallery mechanics). New choices go in `docs/decisions/NNNN-title.md`.

`docs/BACKLOG.md` is the living list of asks: capture a new ask BEFORE starting; when it ships move it under `## Done` with a one-line note and date; unverified code goes under `## P0 - needs verification`.
