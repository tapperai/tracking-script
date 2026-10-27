#!/usr/bin/env bash
# BATCH BISECT (CI standard 2026-10-17). A red test batch names the guilty merge.
#
# Runs in tests.yml's `bisect` job when a batch or nightly run failed. Walks the FIRST-PARENT line (one entry per
# merge) between the newest commit the batch tested green on this branch (GOOD) and the red commit (BAD), running
# BISECT_CMD at each step (`git bisect run`: exit 0 good, 125 skip, anything else bad). The culprit, its PR and its
# author agent go to the run summary, an `::error title=Batch culprit::` annotation, the artifact file
# bisect-result.json, and a comment on the culprit PR. Nothing is reverted or blocked here: Master gets the red run
# as CI_RED in Loop and reverts (prod hurt) or dispatches a fix forward (otherwise).
#
# SECURITY: this job runs merged code (BISECT_CMD at older commits), so it holds a READ-ONLY token (contents:read,
# actions:read, pull-requests:read). The PR comment is posted by the separate `bisect-report` job (no checkout,
# pull-requests:write) from the uploaded bisect-result.json. The script copies itself to $RUNNER_TEMP first, because
# git bisect checks out trees that may not contain (this version of) it.
# Env: GH_TOKEN (read-only), GITHUB_REPOSITORY, BRANCH, BAD (sha), BISECT_CMD (the command that
# exits non-zero on the failure; keep it to the failing suite or files so each step is short), optional GOOD (a 40-hex
# sha: tests.yml passes the dispatch's `base` for a `batch-affected` run, the passed sha the batch was measured from;
# anything else is ignored), TESTS_WORKFLOW (default tests.yml),
# BISECT_MAX_MERGES (the longest range bisected, default 32 = 5 steps; an older GOOD, or none, is set to it),
# BISECT_BUDGET_MINUTES (default 0 = none: the time every step together may take; keep it under the job's
# timeout-minutes), BISECT_LOG (where the step output goes, default $RUNNER_TEMP/batch-bisect.log).
# BOUNDED (T-8838): loop runs 39156510644 and 39173306376 bisected 70 and 91 merges at ~4-7 minutes a step, hit the
# job's 30-minute timeout and left NO bisect-result (it was written only at the end). Now an INCONCLUSIVE result is
# on disk from the start and rewritten at each end, every step runs under the budget, and a spent budget stops
# `git bisect run` (exit 255) and reports how far it narrowed the range. The output is shown live (tee), not hidden.
# Needs a checkout with full history (fetch-depth 0).
set -uo pipefail
if [ -z "${BATCH_BISECT_COPY:-}" ]; then
  self="${RUNNER_TEMP:-/tmp}/batch-bisect.sh"; cp "$0" "$self"; BATCH_BISECT_COPY=1 exec bash "$self" "$@"
fi

REPO="${GITHUB_REPOSITORY:?}"; BRANCH="${BRANCH:?}"; BAD="${BAD:?}"; CMD="${BISECT_CMD:?}"
WF="${TESTS_WORKFLOW:-tests.yml}"; MAXR="${BISECT_MAX_MERGES:-32}"
LOG="${BISECT_LOG:-${RUNNER_TEMP:-/tmp}/batch-bisect.log}"; : > "$LOG"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"; OUT="${BISECT_OUT:-bisect-result.json}"
BUDGET="${BISECT_BUDGET_MINUTES:-0}"; DEADLINE=0
[ "$BUDGET" -gt 0 ] 2>/dev/null && DEADLINE=$(( $(date +%s) + BUDGET * 60 ))
SPENT="${RUNNER_TEMP:-/tmp}/batch-bisect.spent"; rm -f "$SPENT"
say() { printf '%s\n' "$*" | tee -a "$SUMMARY"; }
write_result() { # <status> <culprit> <pr> <author> <untested-csv> <note>: the file only
  jq -n --arg status "$1" --arg culprit "$2" --arg pr "$3" --arg author "$4" --arg skipped "$5" --arg note "$6" \
    --arg good "${GOOD:-}" --arg bad "$BAD" --arg branch "$BRANCH" --arg repo "$REPO" \
    '{repo:$repo, branch:$branch, status:$status, culprit_sha:$culprit, pr:($pr|tonumber? // null), author:$author,
      good:$good, bad:$bad, skip_tests_prs:($skipped|split(",")|map(select(length>0))), note:$note}' > "$OUT"
}
result() { write_result "$@"; cat "$OUT" >> "$SUMMARY"; }
# ONE bisect step under the budget, as a script (git bisect run takes a command): BISECT_CMD's own exit code, or 255
# once the budget is spent (before the step, or while it runs: `timeout` stops the step's whole process group), which
# makes `git bisect run` abort instead of counting the step bad.
STEP="${RUNNER_TEMP:-/tmp}/batch-bisect-step.sh"
cat > "$STEP" <<'EOS'
#!/usr/bin/env bash
if [ "${BISECT_DEADLINE:-0}" -gt 0 ]; then
  left=$(( BISECT_DEADLINE - $(date +%s) ))
  if [ "$left" -le 0 ]; then echo "== bisect: the time budget is spent; no further step"; : > "$BISECT_SPENT"; exit 255; fi
  timeout --kill-after=20 "$left" bash -c "$BISECT_STEP_CMD"; rc=$?
  if [ "$(date +%s)" -ge "$BISECT_DEADLINE" ] && { [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; }; then
    echo "== bisect: the time budget ran out during this step"; : > "$BISECT_SPENT"; exit 255
  fi
  exit "$rc"
fi
exec bash -c "$BISECT_STEP_CMD"
EOS
export BISECT_DEADLINE="$DEADLINE" BISECT_STEP_CMD="$CMD" BISECT_SPENT="$SPENT"
step() { bash "$STEP" 2>&1 | tee -a "$LOG"; return "${PIPESTATUS[0]}"; }
spent_note() { echo "the time budget (${BUDGET} min) ran out $1; the bisect did not finish"; }

git fetch --quiet origin "$BRANCH" 2>/dev/null || true
# GOOD comes from the environment only as a full sha (it is a workflow input: never a ref name or an option).
[[ "${GOOD:-}" =~ ^[0-9a-f]{40}$ ]] || GOOD=""
if [ -z "$GOOD" ]; then
  # No `base` given (a `batch` or `nightly` run): the newest green run of the batch family. GOOD_FULL_ONLY=1 (a red
  # NIGHTLY): only a green FULL run proves the whole tree good, so only a run named `(batch)` (the FULL batch with nothing
  # to measure from) or `(nightly)` counts (an allowlist: a `(requested)` run may be mode NONE, an `(on-demand)` or
  # `(affected)` run AFFECTED, and the every-10-merges batch since 2026-10-23, `(batch-affected)`, tested part of the
  # tree). A failure such a run could not see may already be there: with one as GOOD the bisect would say PRE_EXISTING
  # instead of naming the merge. Otherwise the same family the trigger measures from, not the newest green run of ANY
  # reason (an `(affected)` run of one change, a hand `(on-demand)` one: T-10194 review 2). The sha is the leading
  # `Tests <sha>` of the run-name only.
  only='\\((batch|batch-affected|nightly)\\)$'; [ "${GOOD_FULL_ONLY:-}" != 1 ] || only='\\((batch|nightly)\\)$'
  GOOD="$(gh api "repos/$REPO/actions/workflows/$WF/runs?branch=$BRANCH&event=workflow_dispatch&status=success&per_page=30" \
    --jq ".workflow_runs[].display_title | select(test(\"$only\"))" 2>/dev/null \
    | sed -nE 's/^Tests ([0-9a-f]{40}) .*$/\1/p' | head -1 || true)"
fi
if [ -z "$GOOD" ] || ! git merge-base --is-ancestor "$GOOD" "$BAD" 2>/dev/null || [ "$GOOD" = "$BAD" ]; then
  # Nothing to measure from: the newest MAXR merges (not CI_BATCH_SIZE: a batch's range can be longer than one batch of
  # counted merges, and the cap below applies anyway; T-10194 review 2).
  GOOD="$(git rev-list --first-parent --max-count=$((MAXR + 1)) "$BAD" | tail -1)"
  say "No green batch is an ancestor of ${BAD:0:12}; bisecting the last $MAXR merges (from ${GOOD:0:12})."
fi
# A long red stretch keeps the last green end far back (91 merges in run 39173306376): bisect at most MAXR merges. A
# failure older than that shows as PRE_EXISTING below (the batch that first went red names it).
if [ "$(git rev-list --first-parent --count "$GOOD..$BAD")" -gt "$MAXR" ]; then
  GOOD="$(git rev-list --first-parent --max-count=$((MAXR + 1)) "$BAD" | tail -1)"
  say "The last green end is more than $MAXR merges back; bisecting the last $MAXR merges (from ${GOOD:0:12})."
fi
range="$(git rev-list --first-parent "$GOOD..$BAD")"
say "Bisecting $(wc -l <<<"$range" | tr -d ' ') merge(s) on $BRANCH: good ${GOOD:0:12}, bad ${BAD:0:12}$([ "$DEADLINE" -gt 0 ] && echo ", within a ${BUDGET}-minute budget")."
# On disk from the start: a job stopped from outside (timeout, cancel) still uploads a result that says so.
UNFINISHED="the bisect did not finish (the job was stopped before it wrote an end); range ${GOOD:0:12}..${BAD:0:12}"
write_result INCONCLUSIVE "" "" "" "" "$UNFINISHED"

# Merges in the range whose author chose NOT to test them on their own (`Tests: skip`, label ci:skip-tests, or
# `Tests: local`): the batch is their only run on GitHub. A failed `gh api --jq` prints its error body on STDOUT, so the
# answer is accepted only as a line that starts with a numeric PR number; anything else counts as "no PR found".
skipped=""; localrun=""
for c in $range; do
  out="$(gh api "repos/$REPO/commits/$c/pulls" --jq ".[] | select(.merge_commit_sha==\"$c\") | [(.number|tostring), ([.labels[].name]|join(\",\")), ((.body // \"\") | split(\"\\n\") | map(select(test(\"^Tests: *\"; \"i\"))) | (.[0] // \"\"))] | @tsv" 2>/dev/null)" || out=""
  line="$(grep -E $'^[0-9]+\t' <<<"$out" | head -1 || true)"
  [ -n "$line" ] || continue
  p="${line%%$'\t'*}"; rest="${line#*$'\t'}"; labels="${rest%%$'\t'*}"; body_tr="${rest#*$'\t'}"
  tr_commit="$(git log -1 --format=%B "$c" 2>/dev/null | grep -iE '^Tests: *' | tail -1 || true)"
  if grep -qE '(^|,)ci:skip-tests(,|$)' <<<"$labels" || grep -qiE '^Tests: *skip' <<<"$tr_commit"$'\n'"$body_tr"; then
    skipped="${skipped:+$skipped,}$p"
  elif grep -qiE '^Tests: *local' <<<"$tr_commit"$'\n'"$body_tr"; then
    skipped="${skipped:+$skipped,}$p"; localrun="${localrun:+$localrun,}$p"
  fi
done
[ -n "$skipped" ] && say "Merges in this batch that chose not to test on their own (Tests: skip / Tests: local / ci:skip-tests): #${skipped//,/, #}. The batch is their only GitHub run."
[ -n "$localrun" ] && say "Of those, tested locally by their author: #${localrun//,/, #}."

# Is the failure real at BAD? A pass here is a flake (or a runner fault): say so and stop.
write_result INCONCLUSIVE "" "" "" "$skipped" "$UNFINISHED"
git checkout --quiet --detach "$BAD"
step; rc=$?
if [ "$rc" -eq 255 ] && [ -f "$SPENT" ]; then
  say "BISECT: $(spent_note "at the red commit ${BAD:0:12}")."; result INCONCLUSIVE "" "" "" "$skipped" "$(spent_note "at the red commit")"; exit 0
fi
if [ "$rc" -eq 0 ]; then
  say "BISECT: the failure does not reproduce at ${BAD:0:12} (FLAKE or runner fault)."
  result FLAKE "" "" "" "$skipped" "BISECT_CMD passed at the red commit"
  exit 0
fi

# Does the GOOD end pass? If it fails too, the failure predates this batch: naming the first merge of the range would
# blame an innocent change. Say so and stop.
git checkout --quiet --detach "$GOOD"
step; rc=$?
if [ "$rc" -eq 255 ] && [ -f "$SPENT" ]; then
  git checkout --quiet --detach "$BAD"
  say "BISECT: $(spent_note "at the good end ${GOOD:0:12}")."; result INCONCLUSIVE "" "" "" "$skipped" "$(spent_note "at the good end")"; exit 0
fi
if [ "$rc" -ne 0 ]; then
  say "BISECT: the failure is already present at the good end ${GOOD:0:12} (PRE_EXISTING): it predates this batch."
  result PRE_EXISTING "" "" "" "$skipped" "BISECT_CMD fails at the good end too"
  git checkout --quiet --detach "$BAD"
  exit 0
fi
git checkout --quiet --detach "$BAD"

git bisect start --first-parent "$BAD" "$GOOD" >/dev/null
mark="$(wc -c < "$LOG")"
git bisect run bash "$STEP" 2>&1 | tee -a "$LOG"
# The first bad commit is refs/bisect/bad once git says it found it (git's wording varies by version:
# "is the first bad commit" / "is the first 'bad' commit"), so read the ref, not the text.
culprit=""
if tail -c +"$((mark + 1))" "$LOG" | grep -qE "is the first .?bad.? commit"; then culprit="$(git rev-parse --verify -q refs/bisect/bad || true)"; fi
if [ -z "$culprit" ] && [ -f "$SPENT" ]; then
  # How far it got: the culprit is one of the merges after the newest good step, up to the oldest bad one.
  nb="$(git rev-parse --verify -q refs/bisect/bad || echo "$BAD")"
  mapfile -t goods < <(git for-each-ref --format='%(objectname)' 'refs/bisect/good-*')
  [ ${#goods[@]} -gt 0 ] || goods=("$GOOD")
  left="$(git rev-list --first-parent --count "$nb" --not "${goods[@]}")"
  steps="$(git bisect log 2>/dev/null | grep -cE '^git bisect (good|bad|skip)' || true)"
  git bisect reset >/dev/null 2>&1 || true
  note="$(spent_note "after $steps bisect step(s)"): the culprit is one of $left merge(s) ending at ${nb:0:12}"
  say "BISECT: $note."
  result INCONCLUSIVE "" "" "" "$skipped" "$note"
  exit 0
fi
git bisect reset >/dev/null 2>&1 || true
if [ -z "$culprit" ]; then
  say "BISECT: no single culprit (see the log above; the good end may already fail)."
  result INCONCLUSIVE "" "" "" "$skipped" "git bisect named no first bad commit"
  exit 0
fi

pr="$(gh api "repos/$REPO/commits/$culprit/pulls" --jq ".[] | select(.merge_commit_sha==\"$culprit\") | .number" 2>/dev/null | head -1 || true)"
# Author agent: the PR head's author (a merge commit's second parent), else the commit's own author.
if git rev-parse -q --verify "$culprit^2" >/dev/null; then who="$(git log -1 --format='%an <%ae>' "$culprit^2")"; else who="$(git log -1 --format='%an <%ae>' "$culprit")"; fi
title="$(git log -1 --format=%s "$culprit")"
say "BATCH CULPRIT: $culprit ${pr:+PR #$pr} by $who: $title"
echo "::error title=Batch culprit::$culprit ${pr:+PR #$pr} by $who"
result CULPRIT "$culprit" "${pr:-}" "$who" "$skipped" "$title"
exit 0
