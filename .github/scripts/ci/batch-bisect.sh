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
# exits non-zero on the failure; keep it to the failing suite or files so each step is short), optional GOOD,
# CI_BATCH_SIZE (fallback range when no green batch exists), TESTS_WORKFLOW (default tests.yml).
# Needs a checkout with full history (fetch-depth 0).
set -uo pipefail
if [ -z "${BATCH_BISECT_COPY:-}" ]; then
  self="${RUNNER_TEMP:-/tmp}/batch-bisect.sh"; cp "$0" "$self"; BATCH_BISECT_COPY=1 exec bash "$self" "$@"
fi

REPO="${GITHUB_REPOSITORY:?}"; BRANCH="${BRANCH:?}"; BAD="${BAD:?}"; CMD="${BISECT_CMD:?}"
WF="${TESTS_WORKFLOW:-tests.yml}"; N="${CI_BATCH_SIZE:-10}"
LOG="${RUNNER_TEMP:-/tmp}/batch-bisect.log"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"; OUT="${BISECT_OUT:-bisect-result.json}"
say() { printf '%s\n' "$*" | tee -a "$SUMMARY"; }
result() { # <status> <culprit> <pr> <author> <untested-csv> <note>
  jq -n --arg status "$1" --arg culprit "$2" --arg pr "$3" --arg author "$4" --arg skipped "$5" --arg note "$6" \
    --arg good "${GOOD:-}" --arg bad "$BAD" --arg branch "$BRANCH" --arg repo "$REPO" \
    '{repo:$repo, branch:$branch, status:$status, culprit_sha:$culprit, pr:($pr|tonumber? // null), author:$author,
      good:$good, bad:$bad, skip_tests_prs:($skipped|split(",")|map(select(length>0))), note:$note}' > "$OUT"
  cat "$OUT" >> "$SUMMARY"
}

git fetch --quiet origin "$BRANCH" 2>/dev/null || true
if [ -z "${GOOD:-}" ]; then
  GOOD="$(gh api "repos/$REPO/actions/workflows/$WF/runs?branch=$BRANCH&event=workflow_dispatch&status=success&per_page=30" \
    --jq '.workflow_runs[].display_title' 2>/dev/null | grep -oE '[0-9a-f]{40}' | head -1 || true)"
fi
if [ -z "$GOOD" ] || ! git merge-base --is-ancestor "$GOOD" "$BAD" 2>/dev/null || [ "$GOOD" = "$BAD" ]; then
  GOOD="$(git rev-list --first-parent --max-count=$((N + 1)) "$BAD" | tail -1)"
  say "No green batch is an ancestor of ${BAD:0:12}; bisecting the last $N merges (from ${GOOD:0:12})."
fi
range="$(git rev-list --first-parent "$GOOD..$BAD")"
say "Bisecting $(wc -l <<<"$range" | tr -d ' ') merge(s) on $BRANCH: good ${GOOD:0:12}, bad ${BAD:0:12}."

# Merges in the range whose PR said "skip tests" (the batch is their only test).
skipped=""
for c in $range; do
  p="$(gh api "repos/$REPO/commits/$c/pulls" --jq ".[] | select(.merge_commit_sha==\"$c\" and ([.labels[].name]|index(\"ci:skip-tests\"))) | .number" 2>/dev/null | head -1 || true)"
  [ -n "$p" ] && skipped="${skipped:+$skipped,}$p"
done
[ -n "$skipped" ] && say "Merges in this batch labelled ci:skip-tests: #${skipped//,/, #}."

# Is the failure real at BAD? A pass here is a flake (or a runner fault): say so and stop.
git checkout --quiet --detach "$BAD"
if bash -c "$CMD"; then
  say "BISECT: the failure does not reproduce at ${BAD:0:12} (FLAKE or runner fault)."
  result FLAKE "" "" "" "$skipped" "BISECT_CMD passed at the red commit"
  exit 0
fi

# Does the GOOD end pass? If it fails too, the failure predates this batch: naming the first merge of the range would
# blame an innocent change. Say so and stop.
git checkout --quiet --detach "$GOOD"
if ! bash -c "$CMD"; then
  say "BISECT: the failure is already present at the good end ${GOOD:0:12} (PRE_EXISTING): it predates this batch."
  result PRE_EXISTING "" "" "" "$skipped" "BISECT_CMD fails at the good end too"
  git checkout --quiet --detach "$BAD"
  exit 0
fi
git checkout --quiet --detach "$BAD"

git bisect start --first-parent "$BAD" "$GOOD" >/dev/null
git bisect run bash -c "$CMD" > "$LOG" 2>&1
culprit="$(sed -n 's/^\([0-9a-f]\{40\}\) is the first bad commit$/\1/p' "$LOG" | head -1)"
git bisect reset >/dev/null 2>&1 || true
tail -40 "$LOG"
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
