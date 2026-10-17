#!/usr/bin/env bash
# TEST BATCH TRIGGER (CI standard 2026-10-17: no test gate on merges, tests run in batches).
#
# Merges land and deploy with no test wait (CI_GATE_MODE=NONE, an org Actions variable a repo variable of the same
# name overrides). The full test set (.github/workflows/tests.yml: typecheck, lint, every suite) runs:
#   - every CI_BATCH_SIZE merges (org variable, default 10) per long-lived branch: THIS script, on every push;
#   - nightly for each long-lived branch whose head the batch has not tested yet: THIS script, on the schedule;
#   - on demand: `gh workflow run tests.yml -f sha=<sha> -f reason=on-demand` (Loop: `@master run tests <repo> [sha]`),
#     a merge whose PR carries `ci:run-tests`, or a pushed commit with the trailer `Tests: run`.
# A red batch never blocks or undoes what landed: tests.yml bisects the batch to the guilty merge and the red run
# reaches Master in Loop as CI_RED (repo, branch, workflow, sha, run id), with the culprit in the run's bisect result.
#
# Every `ci:skip-tests` merge (label on the PR, or the trailer `Tests: skip (<reason>)`) is written to this run's
# summary (who, PR, reason) so the bisect and Master know which merges were never tested on their own. The batch
# still covers them.
#
# Needs: a checkout with first-parent history (fetch-depth 0, filter blob:none), GH_TOKEN with actions:write and
# pull-requests:read. Env: GITHUB_REPOSITORY, GITHUB_EVENT_NAME, GITHUB_REF_NAME, GITHUB_SHA (set by Actions),
# CI_BATCH_SIZE, TESTS_WORKFLOW (default tests.yml), BATCH_BRANCHES (default "master dev main").
set -euo pipefail

REPO="${GITHUB_REPOSITORY:?}"
WF="${TESTS_WORKFLOW:-tests.yml}"
N="${CI_BATCH_SIZE:-10}"
case "$N" in ''|*[!0-9]*) N=10 ;; esac
[ "$N" -ge 1 ] || N=10
EVENT="${GITHUB_EVENT_NAME:?}"
BRANCHES="${BATCH_BRANCHES:-master dev main}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

say() { printf '%s\n' "$*" | tee -a "$SUMMARY"; }

# The sha the newest batch run of tests.yml on <branch> tested (its run-name is "Tests <sha> (<reason>)"); a cancelled
# run tested nothing. Empty when there is none.
last_tested() {
  gh api "repos/$REPO/actions/workflows/$WF/runs?branch=$1&event=workflow_dispatch&per_page=30" \
    --jq '.workflow_runs[] | select(.conclusion != "cancelled") | .display_title' 2>/dev/null \
    | grep -oE '[0-9a-f]{40}' | head -1 || true
}

dispatch() { # <branch> <sha> <reason>
  gh workflow run "$WF" -R "$REPO" --ref "$1" -f sha="$2" -f reason="$3"
  say "dispatched $WF on $1 at ${2:0:12} (reason: $3)"
}

# The merged PR whose merge commit is <sha> (first match), as "number<TAB>labels(comma)<TAB>merged_by". Empty if none.
pr_of() {
  gh api "repos/$REPO/commits/$1/pulls" \
    --jq ".[] | select(.merge_commit_sha == \"$1\") | [(.number|tostring), ([.labels[].name]|join(\",\")), (.merged_by.login // .user.login // \"\")] | @tsv" \
    2>/dev/null | head -1 || true
}

trailer() { # <sha> <key>: the value of the first trailer <key> in the commit message
  git log -1 --format=%B "$1" | git interpret-trailers --parse | sed -n "s/^$2: *//Ip" | head -1
}

if [ "$EVENT" = "push" ]; then
  BRANCH="${GITHUB_REF_NAME:?}"; HEAD="${GITHUB_SHA:?}"
  # Who asked for what on THIS merge.
  pr="$(pr_of "$HEAD")"; num="$(cut -f1 <<<"$pr")"; labels="$(cut -f2 <<<"$pr")"; who="$(cut -f3 <<<"$pr")"
  skip_tr="$(trailer "$HEAD" Tests || true)"
  if grep -qE '(^|,)ci:skip-tests(,|$)' <<<"$labels" || grep -qi '^skip' <<<"$skip_tr"; then
    reason="$(sed -n 's/^[Ss]kip *(\(.*\))$/\1/p' <<<"$skip_tr")"
    if [ -z "$reason" ] && [ -n "$num" ]; then
      reason="$(gh api "repos/$REPO/issues/$num/comments" --paginate --jq '.[].body' 2>/dev/null | sed -n 's/^Tests skipped[^:]*: *//p' | tail -1 || true)"
    fi
    say "SKIP-TESTS: ${HEAD:0:12} PR ${num:+#$num} by ${who:-$(git log -1 --format=%an "$HEAD")}, reason: ${reason:-not given}. Never tested on its own; the next batch covers it."
  fi
  if grep -qE '(^|,)ci:run-tests(,|$)' <<<"$labels" || grep -qi '^run' <<<"$skip_tr"; then
    dispatch "$BRANCH" "$HEAD" "requested"
    exit 0
  fi
  last="$(last_tested "$BRANCH")"
  if [ -n "$last" ] && git cat-file -e "$last^{commit}" 2>/dev/null && git merge-base --is-ancestor "$last" "$HEAD"; then
    count="$(git rev-list --first-parent --count "$last..$HEAD")"
  else
    count="$N"   # nothing tested yet on this branch (or history rewritten): start a batch now
  fi
  say "$BRANCH: $count merge(s) since the last tested commit ${last:0:12} (batch size $N)."
  if [ "$count" -ge "$N" ]; then dispatch "$BRANCH" "$HEAD" "batch"; fi
  exit 0
fi

# schedule / workflow_dispatch of this trigger: the nightly pass over every long-lived branch.
for b in $BRANCHES; do
  head="$(gh api "repos/$REPO/branches/$b" --jq .commit.sha 2>/dev/null || true)"
  [ -n "$head" ] || continue
  last="$(last_tested "$b")"
  if [ "$last" = "$head" ]; then say "$b: head ${head:0:12} already tested."; continue; fi
  dispatch "$b" "$head" "nightly"
done
