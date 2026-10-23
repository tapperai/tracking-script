#!/usr/bin/env bash
# TEST BATCH TRIGGER (testing policy 2026-10-18, on the CI standard of 2026-10-17: no test gate on merges).
#
# Merges land and deploy with no test wait (CI_GATE_MODE=NONE, an org Actions variable a repo variable of the same
# name overrides). THE AUTHOR OF EACH CHANGE CHOOSES ONE OF THREE, recorded on the change:
#   local     the author ran the tests for the change on their machine and they passed. Trailer
#             `Tests: local (<the exact command>)`. No GitHub run. NOT counted toward a batch.
#   affected  GitHub runs only the tests the change can reach (tests.yml mode AFFECTED). PR label `ci:run-affected`
#             (at the PR) or trailer `Tests: affected` (on the merged commit: THIS script dispatches it).
#             Counted toward a batch.
#   none      a trivial change (docs, copy, a style value): label `ci:skip-tests` or trailer
#             `Tests: skip (<reason>)`. No run. NOT counted toward a batch.
#   unmarked  no choice recorded. Counted toward a batch.
# `ci:run-tests` / `Tests: run` still start the FULL set at once.
#
# The test set (tests.yml) runs:
#   - every CI_BATCH_SIZE merges (org variable, default 10) per long-lived branch that are `affected` or unmarked:
#     THIS script, on every push (a promotion merge counts when ANY change it carries is affected or unmarked). Since
#     2026-10-23 (operator decision, GitHub Actions cost) the batch runs mode AFFECTED against the last tested sha
#     (`base`), reason `batch-affected`: typecheck, lint and only the tests those merges can reach (tests.yml widens
#     to the whole suite by its own rules: dependencies, config, test setup, CI). When there is no tested sha to
#     measure from (nothing tested yet, history rewritten) the batch is FULL, reason `batch`;
#   - ONCE a night per repo, FULL, the single safety net for cross-change breaks, and only when the branch moved
#     (since the last FULL run; an AFFECTED batch does not count as having tested the head): THIS
#     script, on the schedule. A repo with a dev branch tests dev; master only when its tree differs from dev's
#     (master and dev hold the same code, so testing both would be the same run twice);
#   - on demand: `gh workflow run tests.yml -f sha=<sha> -f reason=on-demand` (Loop: `@master run tests <repo> [sha]`).
# A red batch never blocks or undoes what landed: tests.yml bisects the batch to the guilty merge and the red run
# reaches Master in Loop as CI_RED (repo, branch, workflow, sha, run id), with the culprit in the run's bisect result.
# Every `local` and `skip` merge is written to this run's summary (who, PR, command or reason).
#
# Needs: a checkout with first-parent history (fetch-depth 0, filter blob:none), GH_TOKEN with actions:write and
# pull-requests:read. Env: GITHUB_REPOSITORY, GITHUB_EVENT_NAME, GITHUB_REF_NAME, GITHUB_SHA (set by Actions),
# CI_BATCH_SIZE, TESTS_WORKFLOW (default tests.yml), BATCH_BRANCHES (default "master dev main" plus the repo's
# default branch; set, it is taken as listed). A branch the repo does not have is skipped with a line; a repo with no
# active TESTS_WORKFLOW dispatches nothing and ends green.
# Self-test (no network): TRIGGER_SELFTEST=1 bash batch-trigger.sh <function> <args>.
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-}"
WF="${TESTS_WORKFLOW:-tests.yml}"
N="${CI_BATCH_SIZE:-10}"
case "$N" in ''|*[!0-9]*) N=10 ;; esac
[ "$N" -ge 1 ] || N=10
EVENT="${GITHUB_EVENT_NAME:-}"
BRANCHES="${BATCH_BRANCHES:-master dev main}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
API_BUDGET=40   # PR look-ups per run (a labelled change needs one call); past it a change is read by its trailer only

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

# The sha the newest run of tests.yml on <branch> tested (its run-name is "Tests <sha> (<reason>)"); a cancelled run
# tested nothing. A per-merge `affected` run tested only part of the tree, so it never moves the batch baseline. A
# `batch-affected` run (the every-10-merges batch since 2026-10-23, mode AFFECTED) is the baseline of the NEXT batch (it
# measured its merges), but it did not test the whole tree: `strict` (the nightly) skips it, so the nightly stays a FULL
# run of any head no FULL run has tested.
last_tested() { # <branch> [strict]
  local partial='\\(affected\\)$'
  [ "${2:-}" != strict ] || partial='\\((batch-)?affected\\)$'
  gh api "repos/$REPO/actions/workflows/$WF/runs?branch=$1&event=workflow_dispatch&per_page=30" \
    --jq ".workflow_runs[] | select(.conclusion != \"cancelled\") | .display_title | select(test(\"$partial\") | not)" 2>/dev/null \
    | grep -oE '[0-9a-f]{40}' | head -1 || true
}

dispatch() { # <branch> <sha> <reason> [mode] [base]; a ref GitHub does not know is skipped with a line, any other failure is status 1
  local out mode="${4:-FULL}" extra=()
  [ "$mode" = FULL ] || extra=(-f mode="$mode")   # FULL is every tests.yml's default: older copies need no `mode` input
  [ -z "${5:-}" ] || extra+=(-f base="$5")        # AFFECTED only: the commit the change is measured from
  if out="$(gh workflow run "$WF" -R "$REPO" --ref "$1" -f sha="$2" -f reason="$3" ${extra[@]+"${extra[@]}"} 2>&1)"; then
    [ -z "$out" ] || printf '%s\n' "$out"
    say "dispatched $WF on $1 at ${2:0:12} (reason: $3, mode $mode${5:+, base ${5:0:12}})"
  elif grep -q 'No ref found' <<<"$out"; then
    say "$1: GitHub has no ref $1 in $REPO, $WF not dispatched."
  else
    printf '%s\n' "$out" >&2
    return 1
  fi
}

# The merged PR whose merge commit is <sha>, as one line "number<TAB>labels(comma)<TAB>merged_by<TAB>body-trailer";
# empty if none. The body trailer is the first `Tests:` line of the PR description (a squash merge may drop it).
pr_of() {
  gh api "repos/$REPO/commits/$1/pulls" \
    --jq ".[] | select(.merge_commit_sha == \"$1\") | [(.number|tostring), ([.labels[].name]|join(\",\")), (.merged_by.login // .user.login // \"\"), ((.body // \"\") | split(\"\\n\") | map(select(test(\"^Tests: *\"; \"i\"))) | (.[0] // \"\") | sub(\"^Tests: *\"; \"\"; \"i\"))] | @tsv" \
    2>/dev/null | grep -E $'^[0-9]+\t' | head -1 || true
}

trailer() { # <sha> <key>: the value of the first trailer <key> in the commit message
  git log -1 --format=%B "$1" | git interpret-trailers --parse | sed -n "s/^$2: *//Ip" | head -1
}

# <text> -> local | skip | affected | run | (empty = unmarked). <text> is a `Tests:` value or a comma list of labels.
mark_of() {
  local t="${1:-}"
  if   grep -qE '(^|,)ci:run-tests(,|$)' <<<"$t" || grep -qiE '^ *run( |\(|$)' <<<"$t"; then echo run
  elif grep -qE '(^|,)ci:skip-tests(,|$)' <<<"$t" || grep -qiE '^ *skip( |\(|$)' <<<"$t"; then echo skip
  elif grep -qE '(^|,)ci:run-affected(,|$)' <<<"$t" || grep -qiE '^ *affected( |\(|$)' <<<"$t"; then echo affected
  elif grep -qiE '^ *local( |\(|$)' <<<"$t"; then echo local
  fi
}

# The author's choice for one commit: its own trailer, else the PR's labels, else the PR description's trailer.
# Sets CHOICE (local | skip | affected | run | empty = unmarked) and PR_LINE (the PR, when it was looked up). Not run in
# a subshell: the look-up budget is a counter.
CHOICE=""; PR_LINE=""
choice_of() { # <sha> [lookup=yes|no]
  local sha="$1"
  PR_LINE=""
  CHOICE="$(mark_of "$(trailer "$sha" Tests || true)")"
  [ -z "$CHOICE" ] || return 0
  if [ "${2:-yes}" = yes ] && [ "$API_BUDGET" -gt 0 ]; then
    API_BUDGET=$((API_BUDGET - 1))
    PR_LINE="$(pr_of "$sha")"
    if [ -n "$PR_LINE" ]; then
      CHOICE="$(mark_of "$(cut -f2 <<<"$PR_LINE")")"
      [ -n "$CHOICE" ] || CHOICE="$(mark_of "$(cut -f4 <<<"$PR_LINE")")"
    fi
  fi
  return 0
}

# Does the first-parent commit <c> count toward a batch? 0 = yes. local and skip do not. A promotion merge
# (dev -> master, a MERGE commit) counts when ANY commit it carries is affected or unmarked.
counts() { # <sha>
  local c="$1" s
  if [ "$(git rev-list --parents -n1 "$c" | wc -w)" -ge 3 ] && git log -1 --format=%s "$c" | grep -qi 'promote/dev-to-master'; then
    for s in $(git rev-list --no-merges "$c^1..$c^2"); do
      choice_of "$s" no
      case "$CHOICE" in local|skip) ;; *) return 0 ;; esac
    done
    return 1
  fi
  choice_of "$c"
  case "$CHOICE" in local|skip) return 1 ;; *) return 0 ;; esac
}

count_unmarked_or_affected() { # <last> <head>
  local c n=0
  for c in $(git rev-list --first-parent "$1..$2"); do
    if counts "$c"; then n=$((n + 1)); fi
  done
  echo "$n"
}

if [ -n "${TRIGGER_SELFTEST:-}" ]; then "$@"; exit $?; fi

[ -n "$REPO" ] && [ -n "$EVENT" ] || { echo "GITHUB_REPOSITORY and GITHUB_EVENT_NAME are required" >&2; exit 2; }

# No active tests workflow in this repo (not added yet, or disabled): nothing to dispatch, and that is not a failure.
wf_state="$(get_or_absent "repos/$REPO/actions/workflows/$WF" .state)"
if [ "$wf_state" != "active" ]; then
  say "$WF is ${wf_state:-not in this repo}: nothing to dispatch."
  exit 0
fi

if [ "$EVENT" = "push" ]; then
  BRANCH="${GITHUB_REF_NAME:?}"; HEAD="${GITHUB_SHA:?}"
  # Who chose what on THIS merge.
  choice_of "$HEAD"; mark="$CHOICE"; pr="$PR_LINE"
  [ -n "$pr" ] || pr="$(pr_of "$HEAD")"
  num="$(cut -f1 <<<"$pr")"; who="$(cut -f3 <<<"$pr")"; who="${who:-$(git log -1 --format=%an "$HEAD")}"
  tr_val="$(trailer "$HEAD" Tests || true)"; [ -n "$tr_val" ] || tr_val="$(cut -f4 <<<"$pr")"
  case "$mark" in
    skip)
      reason="$(sed -n 's/^[Ss]kip *(\(.*\))$/\1/p' <<<"$tr_val")"
      if [ -z "$reason" ] && [ -n "$num" ]; then
        reason="$(gh api "repos/$REPO/issues/$num/comments" --paginate --jq '.[].body' 2>/dev/null | sed -n 's/^Tests skipped[^:]*: *//p' | tail -1 || true)"
      fi
      say "SKIP-TESTS: ${HEAD:0:12} PR ${num:+#$num} by $who, reason: ${reason:-not given}. Not counted toward a batch; the nightly run covers it."
      ;;
    local)
      say "LOCAL-TESTS: ${HEAD:0:12} PR ${num:+#$num} by $who ran: $(sed -n 's/^[Ll]ocal *(\(.*\))$/\1/p' <<<"$tr_val" | head -1). Not counted toward a batch; the nightly run covers it."
      ;;
  esac
  if [ "$mark" = run ]; then
    dispatch "$BRANCH" "$HEAD" "requested" FULL
    exit 0
  fi
  if [ "$mark" = affected ]; then
    # Chosen at the PR (label or description trailer): tests.yml already ran AFFECTED on the PR. Chosen only on the
    # commit (a direct push, a hotfix): run it now, on the tests the merged change can reach (tests.yml lists the
    # changed files itself: HEAD^1...HEAD).
    if [ "$(mark_of "$(cut -f2 <<<"$pr")")" = affected ] || [ "$(mark_of "$(cut -f4 <<<"$pr")")" = affected ]; then
      say "AFFECTED-TESTS: ${HEAD:0:12} PR ${num:+#$num} by $who chose affected at the PR; that run is its test. Counted toward a batch."
    else
      dispatch "$BRANCH" "$HEAD" "affected" AFFECTED
    fi
  fi
  last="$(last_tested "$BRANCH")"
  measurable=0   # 1 = there is a tested sha to measure the batch from, so the batch can run AFFECTED
  if [ -n "$last" ] && git cat-file -e "$last^{commit}" 2>/dev/null && git merge-base --is-ancestor "$last" "$HEAD"; then
    measurable=1
    count="$(count_unmarked_or_affected "$last" "$HEAD")"
    total="$(git rev-list --first-parent --count "$last..$HEAD")"
  else
    count="$N"; total="$N"   # nothing tested yet on this branch (or history rewritten): start a batch now, FULL
  fi
  say "$BRANCH: $count merge(s) to test since the last tested commit ${last:0:12} ($total merged, the rest chose local or skip; batch size $N)."
  if [ "$count" -ge "$N" ]; then
    # The batch tests what its merges can reach (operator decision 2026-10-23); the nightly FULL run covers the rest.
    if [ "$measurable" = 1 ]; then dispatch "$BRANCH" "$HEAD" "batch-affected" AFFECTED "$last"
    else dispatch "$BRANCH" "$HEAD" "batch" FULL; fi
  fi
  exit 0
fi

# schedule / workflow_dispatch of this trigger: THE nightly run, one per repo, only when the branch moved. With
# BATCH_BRANCHES unset the repo's default branch is always a candidate (tracking-script's is main, tracker-protos' dev).
if [ -z "${BATCH_BRANCHES:-}" ]; then BRANCHES="$(gh api "repos/$REPO" --jq .default_branch) $BRANCHES"; fi
seen=" "; failed=""; have=""
for b in $BRANCHES; do
  case "$seen" in *" $b "*) continue ;; esac
  seen="$seen$b "
  head="$(branch_head "$b")" || { failed="$failed $b"; continue; }
  if [ -z "$head" ]; then say "$b: no such branch in $REPO, skipped."; continue; fi
  have="$have $b:$head"
done
# The head sha of <branch> in $have; empty when it is not there. Status 0 either way: under `set -e` a `[ ] && echo`
# loop ends on the last test, so a branch that is not the last in $have killed the nightly (master-only repos).
head_of() { local kv; for kv in $have; do if [ "${kv%%:*}" = "$1" ]; then echo "${kv#*:}"; fi; done; }
dev_head="$(head_of dev)"
for kv in $have; do
  b="${kv%%:*}"; head="${kv#*:}"
  # master and dev hold the same code: when the trees are equal, dev's run IS master's run.
  if [ -z "${BATCH_BRANCHES:-}" ] && [ "$b" = master ] && [ -n "$dev_head" ]; then
    if [ "$(git rev-parse "$head^{tree}" 2>/dev/null || echo a)" = "$(git rev-parse "$dev_head^{tree}" 2>/dev/null || echo b)" ]; then
      say "$b: same tree as dev (${dev_head:0:12}); dev's nightly run covers it."; continue
    fi
  fi
  last="$(last_tested "$b" strict)"
  if [ "$last" = "$head" ]; then say "$b: head ${head:0:12} already tested."; continue; fi
  dispatch "$b" "$head" "nightly" FULL || failed="$failed $b"
done
if [ -n "$failed" ]; then say "FAILED on:$failed (see the errors above)."; exit 1; fi
