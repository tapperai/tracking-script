# Review guide: tracking-script

A single-file GTM Community Template (`template.tpl`) that loads the Tapper tracker and calls
`tapper.init`. The Gallery serves the commit named by the FIRST `sha` in `metadata.yaml` on `main`,
so a merge alone reaches nobody, and GTM never auto-updates an imported template. This repo is
PUBLIC: findings, like everything else here, stay technical. PR history is short, so this guide
comes from the access_globals defect fixed in tracking-script#7.

## Proof rule

- Every finding cites `path:line` at the reviewed sha (`git show <sha>:template.tpl`), says what a
  container does wrongly, and how you know: the validator or test runner output, or a GTM Preview.
- No `path:line`, no finding.

## Real bugs here (block on these)

- **A permission that does not match the API call**: GTM checks `access_globals` against the exact
  dotted key and operation. tracking-script#7 fixed a grant on `tapper` that did not cover
  `callInWindow('tapper.init', ...)`, so the tag threw on every page. Each window path needs its exact
  key with `execute`, `read` or `write` as the call requires.
- **Permissions wider than needed**: an extra key or operation, an `inject_script` URL with a wildcard
  or different from the literal in the code, `logging` beyond debug. The Gallery review and every
  importer see these.
- **A broken release entry**: the new first `metadata.yaml` `versions` entry must name the real
  template commit of this PR; merges are merge commits only, so that sha survives. A wrong or future
  sha ships the wrong template.
- **Behaviour without a `___TESTS___` scenario**: a new branch in the sandboxed code needs a scenario
  the runner executes.
- **Public-repo leaks**: a customer name, domain, rate, count or internal table name in code comments,
  docs, the PR body or commit messages. Edit history keeps old text.

## Skip

- `Validate template.tpl (pre-deploy gate)` (`.github/workflows/tests.yml`) runs the validator and
  the test runner on every ready PR and is required; do not restate its output.
- Gallery category choices, README wording.

## Checks worth running

- `python3 scripts/validate_template.py template.tpl --metadata metadata.yaml`
- `node scripts/run_template_tests.mjs template.tpl`
