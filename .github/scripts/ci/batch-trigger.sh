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
# CI_BATCH_SIZE, TESTS_WORKFLOW (default tests.yml), BATCH_BRANCHES (default "master dev main" plus the repo's
# default branch). The nightly pass skips, with a line, every listed branch the repo does not have; a repo with no
# active TESTS_WORKFLOW dispatches nothing and ends green.
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

# GET <path> through gh with --jq <filter>: the answer on success; nothing (status 0) when GitHub answers 404; status 1
# on any other failure. gh prints an error body on STDOUT even with --jq, so a failed call's output is never used.
get_or_absent() {
  local out
  if out="$(gh api "$1" --jq "$2" 2>/dev/null)"; then printf '%s\n' "$out"; return 0; fi
  if grep -q '"status": *"404"' <<<"$out"; then return 0; fi
  printf 'gh api %s failed: %s\n' "$1" "${out:0:300}" >&2
  return 1
}

# The head sha of <branch>; empty when the repo has no such branch (a renamed branch's redirect counts as none).
branch_head() {
  local out
  out="$(get_or_absent "repos/$REPO/branches/$1" "select(.name == \"$1\") | .commit.sha")" || return 1
  grep -xE '[0-9a-f]{40}' <<<"$out" || true
}

# No active tests workflow in this repo (not added yet, or disabled): nothing to dispatch, and that is not a failure.
wf_state="$(get_or_absent "repos/$REPO/actions/workflows/$WF" .state)"
if [ "$wf_state" != "active" ]; then
  say "$WF is ${wf_state:-not in this repo}: nothing to dispatch."
  exit 0
fi

# The sha the newest batch run of tests.yml on <branch> tested (its run-name is "Tests <sha> (<reason>)"); a cancelled
# run tested nothing. Empty when there is none.
last_tested() {
  gh api "repos/$REPO/actions/workflows/$WF/runs?branch=$1&event=workflow_dispatch&per_page=30" \
    --jq '.workflow_runs[] | select(.conclusion != "cancelled") | .display_title' 2>/dev/null \
    | grep -oE '[0-9a-f]{40}' | head -1 || true
}

dispatch() { # <branch> <sha> <reason>; a ref GitHub does not know is skipped with a line, any other failure is status 1
  local out
  if out="$(gh workflow run "$WF" -R "$REPO" --ref "$1" -f sha="$2" -f reason="$3" 2>&1)"; then
    [ -z "$out" ] || printf '%s\n' "$out"
    say "dispatched $WF on $1 at ${2:0:12} (reason: $3)"
  elif grep -q 'No ref found' <<<"$out"; then
    say "$1: GitHub has no ref $1 in $REPO, $WF not dispatched."
  else
    printf '%s\n' "$out" >&2
    return 1
  fi
}

# The merged PR whose merge commit is <sha> (first match), as "number<TAB>labels(comma)<TAB>merged_by". Empty if none.
pr_of() {
  gh api "repos/$REPO/commits/$1/pulls" \
    --jq ".[] | select(.merge_commit_sha == \"$1\") | [(.number|tostring), ([.labels[].name]|join(\",\")), (.merged_by.login // .user.login // \"\")] | @tsv" \
    2>/dev/null | grep -E $'^[0-9]+\t' | head -1 || true
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

# schedule / workflow_dispatch of this trigger: the nightly pass over every long-lived branch the repo has. With
# BATCH_BRANCHES unset the repo's default branch is always one of them (tracking-script's is main, tracker-protos' dev).
if [ -z "${BATCH_BRANCHES:-}" ]; then BRANCHES="$(gh api "repos/$REPO" --jq .default_branch) $BRANCHES"; fi
seen=" "; failed=""
for b in $BRANCHES; do
  case "$seen" in *" $b "*) continue ;; esac
  seen="$seen$b "
  head="$(branch_head "$b")" || { failed="$failed $b"; continue; }
  if [ -z "$head" ]; then say "$b: no such branch in $REPO, skipped."; continue; fi
  last="$(last_tested "$b")"
  if [ "$last" = "$head" ]; then say "$b: head ${head:0:12} already tested."; continue; fi
  dispatch "$b" "$head" "nightly" || failed="$failed $b"
done
if [ -n "$failed" ]; then say "FAILED on:$failed (see the errors above)."; exit 1; fi
