## Document First Development

**Every new feature or significant change must have a spec in `docs/` before implementation begins.** Skip steps 1-5 only if the user explicitly asks to write code directly (e.g., "just fix this", "skip the spec").

**Docs here:** decisions in `docs/decisions/NNNN-title.md` (short, frozen, a newer record supersedes an old one); how each area works now in `docs/<area>.md` (one page per area, about 300 lines, updated by the PR that changes the area). The rule is the `docs-rule` skill in loop.

1. **Before implementing any feature or significant change**, read the rules:
   - Read the `docs-rule` skill in loop for spec rules, structure, and conventions
2. Before writing code, check if a spec exists at `docs/{domain}/SPEC.md`
3. If no spec exists, create one from `docs/_templates/SPEC.md` first
4. **After writing the spec, open the file, record the decisions it locks in (what you measured, what would have made the answer no), and implement straight away.** No confirmation wait: agents decide from evidence and record the decision in the spec.
5. Implement from the spec and follow it exactly. Break the spec into independent work streams and **spawn parallel agents** (one per work stream) to maximize speed. Sequence dependent work — implement dependencies first, then parallelize everything that follows
6. After implementing, update the spec to match what was built — keep specs and code in sync at all times. Mark `Implemented in:` with the current repo name. Move completed items out of Remaining Work. Mark any sections that are designed but not yet coded as `PLANNED`
7. **For doc commands** (e.g., `Check spec drift`, full rerun, setup) — follow the `docs-rule` skill in loop

## Backlog Discipline

`docs/BACKLOG.md` is the single living list of every TODO the user has called out, **including ones that have already been shipped**.

- When the user asks for something new, capture it in `docs/BACKLOG.md` *before* starting work — under the right priority (`P0` / `P1` / `P2`).
- When something ships, **don't delete it** — move it under `## Done` with a one-line note + the date so we can audit what landed and when.
- Items that exist as code but the user has not yet seen working live in `## P0 — needs verification`.
- Never silently drop a request. If you push back on scope, write the rationale inline next to the entry.
- Treat `docs/BACKLOG.md` as authoritative when the user says "did you do X" — search there first before re-reading code or git log.

## Public repo

This repo is PUBLIC. Keep customer names, customer counts, rates, domains, internal table or dataset names and operator quotes out of every commit, PR, issue, comment and doc. Describe the technical change only; put the why and the evidence in a private repo (its `docs/BACKLOG.md` or a private twin PR). GitHub keeps every earlier revision of a PR, issue or comment body in its public edit history, so editing the text later does not remove it.

## What this repo is and its gate

A single GTM Community Template, `template.tpl`: it injects `https://monitor.tapper.ai/bundle.js` and calls `tapper.init(pk)`, with `access_globals` execute granted on the exact key `tapper.init`. No build, no package.json. Run the CI gate locally from the repo root before marking a PR ready (stdlib Python and Node only; the `--metadata` check needs full git history):

```
python3 scripts/validate_template.py template.tpl --metadata metadata.yaml
node scripts/run_template_tests.mjs template.tpl
```

## Deploy

There is no deploy job. The GTM Community Template Gallery serves the `template.tpl` of the commit named by the FIRST `sha` in `metadata.yaml` on `main`, not `main` HEAD, and picks up a new first entry in typically 2-3 days. A merge that changes `template.tpl` reaches no customer until that commit's sha is the first `metadata.yaml` entry. GTM never auto-updates an imported template: each container that imported it has to accept the update in a workspace and publish. Merges are merge commits only (squash and rebase are disabled), so the sha `metadata.yaml` names survives the merge. Merges are direct (`gh pr merge <n> --merge`; no merge queue). CI standard 2026-10-17: the one test workflow is `.github/workflows/tests.yml`. Its pre-deploy check `Validate template.tpl (pre-deploy gate)` (about 10 seconds) runs on every ready PR in every gate mode and stays a hard stop: ruleset `required-checks` on `main` requires it next to `CI gate`, which follows the Actions variable `CI_GATE_MODE` (`NONE` today: skipped, which counts as passing). Labels `ci:skip-tests` / `ci:run-tests` switch the mode per PR; `test-batch.yml` runs the set every `CI_BATCH_SIZE` merges, nightly and on demand (`gh workflow run tests.yml -R tapperai/tracking-script --ref main -f sha=<sha> -f reason=on-demand`) and bisects a red run to the guilty merge. Drafts run nothing; there is no push run. To see what the Gallery serves right now, read `versions[0].sha` and `permission` from https://tagmanager.google.com/api/gallery/owners/tapperai/templates/tracking-script (the undocumented JSON behind the Gallery page; drop its first line). Details: `docs/tracking-script/ENVIRONMENT_SPINUP.md` (CI/CD).

## Testing a change (policy 2026-10-18)

The author of each change chooses ONE of three, per change, and records it:
1. **Local** (default for code): run the tests for your change on your machine; if they pass, merge with no GitHub test run.
   Trailer `Tests: local (<the exact command you ran>)`.
2. **Affected on GitHub**: GitHub runs only the tests the change can reach (`tests.yml` mode AFFECTED), for that PR only.
   Label `ci:run-affected`, or the line `Tests: affected` in the PR description; on a commit that lands with no PR-time run,
   the trailer `Tests: affected` makes the batch trigger dispatch it at merge.
3. **None** (trivial: docs, copy, a style value): trailer `Tests: skip (<reason>)`, or label `ci:skip-tests`.
`ci:run-tests` / `Tests: run` still starts the FULL suite on request.

**The ONE local command:** `node scripts/test-changed.mjs` (`scripts/test-changed.*`; `-- --list` prints the selection only, `-- --base <ref>`). It takes
everything changed since the merge-base with `origin/main` (commits, staged, unstaged, untracked), then runs the two checks tests.yml runs: `python3 scripts/validate_template.py template.tpl --metadata metadata.yaml` and `node scripts/run_template_tests.mjs template.tpl` (the whole set, a few seconds) unless the change is prose only. AFFECTED in tests.yml runs the same single job.
It prints `Tests selected: N ...` and what it ran, and on success `PASSED. Put in the commit and the PR description: Tests: local (...)`. The pre-deploy check `Validate template.tpl` is a required hard stop and runs on every ready PR whatever you recorded (one billed minute, it guards the branch Google's Gallery reads), so a recorded local or none choice saves the batch, not that check.

**Trailer placement:** the last paragraph of the commit message AND of the PR description (a squash merge keeps it).
**Batches and nightly:** every `CI_BATCH_SIZE` (10) merges per branch the FULL suite runs, counting ONLY `affected` and unmarked
changes (`local` and `skip` are not counted); ONE nightly FULL run (01:41 UTC) as the safety net, only when the branch moved. A red batch **bisects** to the guilty
merge (every failed check re-runs) and says which merges chose not to test on their own. Mechanics: `.github/workflows/tests.yml` header.
