#!/usr/bin/env bash
# Local test of batch-trigger.sh's baseline rule (no network, nothing on GitHub): a fake `gh` answers from a fixture and
# applies the script's real --jq filter with jq. Run: bash .github/scripts/ci/batch-trigger.test.sh [path/to/batch-trigger.sh]
# Covers: a cancelled run that ran past CANCELLED_TESTED_AFTER_MIN is the new baseline (no re-dispatch on the next push),
# a run cancelled sooner is not, the nightly keeps the strict rule, failure and success still count, `affected` never does;
# the batch runs AFFECTED from the last tested sha (reason batch-affected, a baseline for the next batch but never for the
# nightly), and FULL when there is nothing to measure from; the time window (CI_BATCH_MIN_INTERVAL_MIN, CI_BATCH_MAX) and
# the promotion rule (a dev -> master promotion counts toward no master batch when the repo has dev), T-10194; and the
# T-10194 review: CI_BATCH_MAX counts every first-parent merge, a deferred tail goes with the nightly, a merge with code of
# its own (tree differs from its dev side) counts, only the leading `Tests <sha>` of a run-name is a tested sha, and the
# baseline and the AFFECTED base are on the first-parent line, the base from a PASSED batch, batch-affected or nightly run.
set -euo pipefail
SCRIPT="$(cd "$(dirname "${1:-$(dirname "$0")/batch-trigger.sh}")" && pwd)/$(basename "${1:-batch-trigger.sh}")"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'G'
#!/usr/bin/env bash
# fake gh: `gh api <path> --jq <filter>` answers from $FIXTURE (runs) through real jq; `gh workflow run` is logged.
if [ "$1" = workflow ]; then echo "$*" >> "$GH_LOG"; exit 0; fi
path="$2"; shift 2; filter=""
while [ $# -gt 0 ]; do case "$1" in --jq) filter="$2"; shift 2 ;; *) shift ;; esac; done
case "$path" in
  */actions/workflows/tests.yml) echo active ;;
  */actions/workflows/tests.yml/runs*) jq -r "{workflow_runs: .} | $filter" "$FIXTURE" ;;
  */branches/*) git rev-parse HEAD ;;
  */commits/*/pulls) : ;;
  *) : ;;
esac
G
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" GH_LOG="$T/gh.log" FIXTURE="$T/runs.json" GITHUB_REPOSITORY=o/r
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: want '$3' got '$2'" >&2; fi; }
S1=1111111111111111111111111111111111111111 S2=2222222222222222222222222222222222222222 S3=3333333333333333333333333333333333333333
# run <conclusion> <minutes> <sha> <reason> [start]
run() { jq -n --arg c "$1" --argjson m "$2" --arg s "$3" --arg r "$4" \
  '{conclusion:$c, run_started_at:"2026-10-22T10:00:00Z", updated_at:("2026-10-22T10:00:00Z"|fromdateiso8601+($m*60)|todate), display_title:("Tests "+$s+" ("+$r+")")}'; }
fixture() { jq -s '.' > "$FIXTURE"; }
last() { TRIGGER_SELFTEST=1 bash "$SCRIPT" last_tested "$@"; }

# 1 a cancelled batch that ran 16 minutes is the baseline; strict (the nightly) skips it
{ run cancelled 16 $S3 batch; run success 9 $S1 batch; } | fixture
ok "timed-out batch is the baseline"            "$(last master)"        "$S3"
ok "nightly stays strict"                       "$(last master strict)" "$S1"
# 2 a run cancelled at once (superseded) is not
{ run cancelled 0 $S3 on-demand; run success 9 $S1 batch; } | fixture
ok "superseded run is ignored"                  "$(last master)"        "$S1"
# 3 the threshold: 4 minutes no, 5 minutes yes
{ run cancelled 4 $S3 batch; run success 9 $S1 batch; } | fixture
ok "4 minutes is not enough"                    "$(last master)"        "$S1"
{ run cancelled 5 $S3 batch; run success 9 $S1 batch; } | fixture
ok "5 minutes counts"                           "$(last master)"        "$S3"
ok "threshold is tunable"                       "$(CANCELLED_TESTED_AFTER_MIN=6 last master)" "$S1"
# 4 failure and success still count; an affected run never does, however long it ran
{ run failure 3 $S3 batch; run success 9 $S1 batch; } | fixture
ok "a short failure counts"                     "$(last master)"        "$S3"
{ run cancelled 20 $S3 affected; run cancelled 20 $S2 'affected'; run success 9 $S1 nightly; } | fixture
ok "affected never counts"                      "$(last master)"        "$S1"
# 5 a run with no start time cannot prove it ran: not counted
{ run cancelled 20 $S3 batch | jq 'del(.run_started_at)'; run success 9 $S1 batch; } | fixture
ok "no start time is not counted"               "$(last master)"        "$S1"

# 6 end to end: ten merges after a timed-out batch do not send a second batch right away; ten more do
R="$T/repo"; git init -q -b master "$R"; cd "$R"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
for i in $(seq 1 25); do git commit -q --allow-empty -m "c$i"; done
c() { git rev-parse "master~$((25 - $1))"; }   # c 1 = first commit, c 25 = head
{ run cancelled 16 "$(c 10)" batch; run success 9 "$(c 1)" batch; } | fixture
: > "$GH_LOG"
export GITHUB_EVENT_NAME=push GITHUB_REF_NAME=master CI_BATCH_SIZE=10
GITHUB_SHA="$(c 15)" bash "$SCRIPT" >/dev/null
ok "5 merges after the timed-out batch: no dispatch" "$(grep -c 'workflow run' "$GH_LOG" || true)" "0"
GITHUB_SHA="$(c 20)" bash "$SCRIPT" >/dev/null
ok "10 merges after it: one batch"                   "$(grep -c 'workflow run' "$GH_LOG" || true)" "1"
# the old rule would have sent a batch on every push here: the timed-out run is not a baseline for it
: > "$GH_LOG"; { run cancelled 0 "$(c 10)" batch; run success 9 "$(c 1)" batch; } | fixture
GITHUB_SHA="$(c 15)" bash "$SCRIPT" >/dev/null
ok "a batch cancelled at once is still re-sent"      "$(grep -c 'workflow run' "$GH_LOG" || true)" "1"
# 7 nightly: a timed-out batch on the head does not stop the nightly (strict), a finished one does
: > "$GH_LOG"; { run cancelled 16 "$(c 25)" batch; run success 9 "$(c 1)" batch; } | fixture
GITHUB_EVENT_NAME=schedule BATCH_BRANCHES=dev bash "$SCRIPT" >/dev/null
ok "nightly still runs after a timed-out batch"      "$(grep -c 'workflow run' "$GH_LOG" || true)" "1"
: > "$GH_LOG"; { run failure 16 "$(c 25)" batch; run success 9 "$(c 1)" batch; } | fixture
GITHUB_EVENT_NAME=schedule BATCH_BRANCHES=dev bash "$SCRIPT" >/dev/null
ok "nightly skips a head a batch already finished"   "$(grep -c 'workflow run' "$GH_LOG" || true)" "0"

# 8 the batch runs AFFECTED since 2026-10-23: reason batch-affected, measured from the last tested sha
{ run success 9 "$(c 1)" batch; } | fixture
: > "$GH_LOG"; GITHUB_EVENT_NAME=push GITHUB_SHA="$(c 11)" bash "$SCRIPT" >/dev/null
ok "10 merges after a tested sha: one AFFECTED batch"   "$(grep -c 'workflow run' "$GH_LOG" || true)" "1"
ok "reason batch-affected"                              "$(grep -c 'reason=batch-affected' "$GH_LOG" || true)" "1"
ok "mode AFFECTED"                                      "$(grep -c 'mode=AFFECTED' "$GH_LOG" || true)" "1"
ok "base is the last tested sha"                        "$(grep -c "base=$(c 1)" "$GH_LOG" || true)" "1"
ok "sha is the head"                                    "$(grep -c "sha=$(c 11)" "$GH_LOG" || true)" "1"
# 8b nothing tested yet: there is nothing to measure from, so the batch is FULL with no base
: > "$FIXTURE"; echo '[]' > "$FIXTURE"; : > "$GH_LOG"; GITHUB_EVENT_NAME=push GITHUB_SHA="$(c 11)" bash "$SCRIPT" >/dev/null
ok "no tested sha: one batch"                           "$(grep -c 'workflow run' "$GH_LOG" || true)" "1"
ok "no tested sha: reason batch (FULL)"                 "$(grep -c 'reason=batch$' "$GH_LOG" || true)" "1"
ok "no tested sha: no mode input (FULL is the default)" "$(grep -c 'mode=' "$GH_LOG" || true)" "0"
ok "no tested sha: no base"                             "$(grep -c 'base=' "$GH_LOG" || true)" "0"
# 8c an AFFECTED batch is the baseline of the next batch (no second batch on the next push) ...
{ run success 9 "$(c 11)" batch-affected; run success 9 "$(c 1)" batch; } | fixture
ok "batch-affected is the batch baseline"               "$(last master)" "$(c 11)"
: > "$GH_LOG"; GITHUB_EVENT_NAME=push GITHUB_SHA="$(c 15)" bash "$SCRIPT" >/dev/null
ok "5 merges after an AFFECTED batch: no dispatch"      "$(grep -c 'workflow run' "$GH_LOG" || true)" "0"
: > "$GH_LOG"; GITHUB_EVENT_NAME=push GITHUB_SHA="$(c 21)" bash "$SCRIPT" >/dev/null
ok "10 merges after it: the next AFFECTED batch, from it" "$(grep -c "base=$(c 11)" "$GH_LOG" || true)" "1"
# 8d ... but it did not test the whole tree: the nightly (strict) skips it and still runs FULL on that head
ok "nightly baseline skips batch-affected"              "$(last master strict)" "$(c 1)"
: > "$GH_LOG"; { run success 9 "$(c 25)" batch-affected; run success 9 "$(c 1)" nightly; } | fixture
GITHUB_EVENT_NAME=schedule BATCH_BRANCHES=dev bash "$SCRIPT" >/dev/null
ok "nightly runs FULL on a head only an AFFECTED batch tested" "$(grep -c 'workflow run' "$GH_LOG" || true)" "1"
ok "that nightly is FULL (no mode input)"               "$(grep -c 'mode=' "$GH_LOG" || true)" "0"
: > "$GH_LOG"; { run success 9 "$(c 25)" nightly; } | fixture
GITHUB_EVENT_NAME=schedule BATCH_BRANCHES=dev bash "$SCRIPT" >/dev/null
ok "nightly skips a head a FULL run tested"             "$(grep -c 'workflow run' "$GH_LOG" || true)" "0"

# 8e the nightly baseline is an ALLOWLIST (`batch`, `nightly`): a `requested` run may be mode NONE, an `on-demand` run any mode
{ run success 9 "$(c 25)" requested; run success 9 "$(c 24)" on-demand; run success 9 "$(c 23)" affected; run success 9 "$(c 22)" batch-affected; run success 9 "$(c 1)" nightly; } | fixture
ok "nightly baseline skips requested, on-demand, affected, batch-affected" "$(last master strict)" "$(c 1)"
ok "the batch baseline still takes a requested run"     "$(last master)" "$(c 25)"
: > "$GH_LOG"; { run success 9 "$(c 25)" requested; run success 9 "$(c 1)" nightly; } | fixture
GITHUB_EVENT_NAME=schedule BATCH_BRANCHES=dev bash "$SCRIPT" >/dev/null
ok "nightly runs FULL on a head only a requested run tested" "$(grep -c 'workflow run' "$GH_LOG" || true)" "1"

# 9 the time window (T-10194): a due batch waits until the newest batch on the branch is CI_BATCH_MIN_INTERVAL_MIN old
NOW="$(date -u -d 2026-10-24T12:00:00Z +%s)"
# runat <conclusion> <sha> <reason> <created_at>: a run dispatched at <created_at>
runat() { run "$1" 9 "$2" "$3" | jq --arg t "$4" '.created_at = $t'; }
batch_push() { : > "$GH_LOG"; GITHUB_EVENT_NAME=push BATCH_NOW="$NOW" "$@" bash "$SCRIPT" > "$T/out.txt"; grep -c 'workflow run' "$GH_LOG" || true; }
{ runat success "$(c 11)" batch-affected 2026-10-24T11:40:00Z; } | fixture
ok "10 merges 20 min after the last batch: deferred"   "$(batch_push env GITHUB_SHA="$(c 21)")" "0"
ok "the deferral is said in the summary"               "$(grep -c 'deferred' "$T/out.txt" || true)" "1"
{ runat success "$(c 11)" batch-affected 2026-10-24T10:59:00Z; } | fixture
ok "10 merges 61 min after the last batch: one batch"  "$(batch_push env GITHUB_SHA="$(c 21)")" "1"
{ runat success "$(c 11)" batch-affected 2026-10-24T11:00:00Z; } | fixture
ok "exactly the window (60 min): one batch"            "$(batch_push env GITHUB_SHA="$(c 21)")" "1"
{ runat success "$(c 11)" batch-affected 2026-10-24T11:40:00Z; } | fixture
ok "window 0 is the old rule: one batch"               "$(batch_push env CI_BATCH_MIN_INTERVAL_MIN=0 GITHUB_SHA="$(c 21)")" "1"
ok "window is tunable (15 min): one batch"             "$(batch_push env CI_BATCH_MIN_INTERVAL_MIN=15 GITHUB_SHA="$(c 21)")" "1"
ok "CI_BATCH_MAX waiting merges go inside the window"  "$(batch_push env CI_BATCH_MAX=10 GITHUB_SHA="$(c 21)")" "1"
ok "below CI_BATCH_MAX they wait"                      "$(batch_push env CI_BATCH_MAX=11 GITHUB_SHA="$(c 21)")" "0"
ok "fewer than CI_BATCH_SIZE: no batch, window or not" "$(batch_push env CI_BATCH_MIN_INTERVAL_MIN=0 GITHUB_SHA="$(c 20)")" "0"
# only a batch opens the window: a recent nightly, affected or on-demand run does not defer it
{ runat success "$(c 11)" nightly 2026-10-24T11:55:00Z; runat success "$(c 11)" affected 2026-10-24T11:56:00Z; runat success "$(c 11)" batch 2026-10-24T09:00:00Z; } | fixture
ok "a recent nightly does not defer a batch"           "$(batch_push env GITHUB_SHA="$(c 21)")" "1"
{ runat success "$(c 11)" batch 2026-10-24T11:50:00Z; } | fixture
ok "a recent FULL batch opens the window too"          "$(batch_push env GITHUB_SHA="$(c 21)")" "0"
ok "the deferred batch is unchanged once the window passes" "$(batch_push env BATCH_NOW="$(date -u -d 2026-10-24T12:51:00Z +%s)" GITHUB_SHA="$(c 21)")" "1"
ok "... and it is the AFFECTED batch from the baseline" "$(grep -c "reason=batch-affected.*base=$(c 11)\|base=$(c 11).*reason=batch-affected" "$GH_LOG" || true)" "1"
# 9b a deferred tail on a branch that then goes quiet: the nightly tests that head FULL (T-10194 review: no hourly
#    trigger; a branch below CI_BATCH_SIZE merges waits for the nightly the same way)
git checkout -q --detach "$(c 21)"
{ runat success "$(c 11)" batch-affected 2026-10-24T11:40:00Z; } | fixture
ok "a quiet branch's tail: deferred at the push"       "$(batch_push env GITHUB_SHA="$(c 21)")" "0"
: > "$GH_LOG"; GITHUB_EVENT_NAME=schedule BATCH_BRANCHES=master bash "$SCRIPT" >/dev/null
ok "... the nightly then runs on that head"            "$(grep -c "sha=$(c 21) -f reason=nightly" "$GH_LOG" || true)" "1"
ok "... FULL (no mode input)"                          "$(grep -c 'mode=' "$GH_LOG" || true)" "0"
git checkout -q master
# 9c the AFFECTED batch's base is the newest PASSED (batch), (batch-affected) or (nightly) run on the line (T-10194
#    review); the count still starts at the newest TESTED one, so a red or timed-out batch does not send a batch per push
{ runat failure "$(c 11)" batch-affected 2026-10-24T09:00:00Z; run success 9 "$(c 8)" on-demand; run success 9 "$(c 3)" batch; } | fixture
ok "10 merges after a red batch: one batch"            "$(batch_push env GITHUB_SHA="$(c 21)")" "1"
ok "... measured from the newest PASSED batch run"     "$(grep -c "reason=batch-affected.*base=$(c 3)\$" "$GH_LOG" || true)" "1"
ok "5 merges after the red batch: no batch"            "$(batch_push env GITHUB_SHA="$(c 16)")" "0"
{ run cancelled 16 "$(c 11)" batch; run success 9 "$(c 5)" nightly; } | fixture
ok "10 merges after a timed-out batch: one batch"      "$(batch_push env GITHUB_SHA="$(c 21)")" "1"
ok "... measured from the passed nightly, not from it" "$(grep -c "base=$(c 5)\$" "$GH_LOG" || true)" "1"
{ run success 9 "$(c 11)" requested; run failure 9 "$(c 6)" batch; } | fixture
ok "nothing PASSED on the line: one batch"             "$(batch_push env GITHUB_SHA="$(c 21)")" "1"
ok "... FULL, with no base"                            "$(grep -c 'reason=batch$' "$GH_LOG" || true)" "1"

# 10 a dev -> master promotion counts toward no master batch when the repo has dev (dev counted and batched each change)
P="$T/promo"; git init -q -b master "$P"; cd "$P"
git commit -q --allow-empty -m base; BASE="$(git rev-parse HEAD)"
git checkout -q -b dev
for i in $(seq 1 10); do
  git checkout -q dev; git commit -q --allow-empty -m "change $i"
  git checkout -q master; git merge -q --no-ff dev -m "Merge pull request #$i from tapperai/promote/dev-to-master"
done
PHEAD="$(git rev-parse HEAD)"
{ run success 9 "$BASE" batch; } | fixture
ok "10 promotions, no dev branch: counted (old rule)"  "$(batch_push env GITHUB_SHA="$PHEAD" CI_BATCH_MIN_INTERVAL_MIN=0)" "1"
git update-ref refs/remotes/origin/dev dev
ok "10 promotions on master with dev: no master batch" "$(batch_push env GITHUB_SHA="$PHEAD" CI_BATCH_MIN_INTERVAL_MIN=0)" "0"
ok "... and the summary says dev counted it"          "$(grep -c 'holds only changes dev already counted' "$T/out.txt" || true)" "1"
echo '[]' > "$FIXTURE"
ok "a promotion push needs no baseline (no FULL batch)" "$(batch_push env GITHUB_SHA="$PHEAD" CI_BATCH_MIN_INTERVAL_MIN=0)" "0"
ok "a master head already on dev (fast-forward): none" "$(batch_push env GITHUB_SHA="$(git rev-parse dev~7)" CI_BATCH_MIN_INTERVAL_MIN=0)" "0"
{ run success 9 "$BASE" batch; } | fixture
for i in $(seq 1 10); do git commit -q --allow-empty -m "hotfix $i"; done
ok "5 hotfixes after 10 promotions: no batch (5 count)" "$(batch_push env GITHUB_SHA="$(git rev-parse HEAD~5)" CI_BATCH_MIN_INTERVAL_MIN=0)" "0"
ok "... the summary counts the 5 hotfixes only"        "$(grep -c '^master: 5 merge(s) to test' "$T/out.txt" || true)" "1"
ok "10 direct hotfixes on master still count"         "$(batch_push env GITHUB_SHA="$(git rev-parse HEAD)" CI_BATCH_MIN_INTERVAL_MIN=0)" "1"
# back-end names its promotion "Merge pull request #N from tapperai/dev": what decides is that the merged side is on dev
HF="$(git rev-parse HEAD)"
git checkout -q dev; git commit -q --allow-empty -m "dev change"; git update-ref refs/remotes/origin/dev dev
git checkout -q master; git merge -q --no-ff dev -m "Merge pull request #3412 from tapperai/dev"
ok "a promotion named after dev, pushed: nothing counted" "$(batch_push env GITHUB_SHA="$(git rev-parse HEAD)" CI_BATCH_MIN_INTERVAL_MIN=0)" "0"
ok "... said in the summary"                           "$(grep -c 'holds only changes dev already counted' "$T/out.txt" || true)" "1"
{ run success 9 "$HF" batch; } | fixture
git checkout -q -b fix/x master; git commit -q --allow-empty -m "hotfix by PR"; git checkout -q master
for i in $(seq 1 9); do git commit -q --allow-empty -m "more hotfix $i"; done
git merge -q --no-ff fix/x -m "Merge pull request #3410 from tapperai/fix/x"
ok "a hotfix PR merged to master counts (merged side not on dev)" "$(batch_push env GITHUB_SHA="$(git rev-parse HEAD)" CI_BATCH_MIN_INTERVAL_MIN=0)" "1"
ok "... 10 counted: 9 hotfixes and the hotfix merge, not the promotion" "$(grep -c '^master: 10 merge(s) to test' "$T/out.txt" || true)" "1"
ok "on dev the promotion rule does not apply"          "$(GITHUB_REF_NAME=dev batch_push env GITHUB_SHA="$PHEAD" CI_BATCH_MIN_INTERVAL_MIN=0)" "1"

# 11 the batch baseline is the newest tested sha ON THE BRANCH'S LINE: a hand dispatch on master that tested a PR head
#    (free-text reason) is skipped, not taken as "nothing to measure from" (that made the batch FULL; loop 2026-10-24)
git checkout -q -b side "$BASE"; git commit -q --allow-empty -m "a PR head"; OFF="$(git rev-parse HEAD)"; git checkout -q master
MHEAD="$(git rev-parse master)"
{ runat failure "$OFF" "affected rerun after loop#2913 heap fix" 2026-10-24T09:00:00Z; run success 9 "$PHEAD" nightly; } | fixture
ok "an off-line dispatch is not the baseline"         "$(TRIGGER_SELFTEST=1 bash "$SCRIPT" last_tested_on_line master "$MHEAD")" "$PHEAD"
ok "10 merges after the on-line baseline: one batch"  "$(batch_push env GITHUB_SHA="$MHEAD" CI_BATCH_MIN_INTERVAL_MIN=0)" "1"
ok "... AFFECTED from the on-line baseline, not FULL" "$(grep -c "reason=batch-affected.*base=$PHEAD" "$GH_LOG" || true)" "1"
ok "5 merges after it: no batch (was a FULL batch)"   "$(batch_push env GITHUB_SHA="$(git rev-list --first-parent --reverse "$PHEAD..master" | sed -n 5p)" CI_BATCH_MIN_INTERVAL_MIN=0)" "0"
{ runat failure "$OFF" "on-demand" 2026-10-24T09:00:00Z; } | fixture
ok "only off-line runs: nothing to measure, FULL"     "$(batch_push env GITHUB_SHA="$MHEAD" CI_BATCH_MIN_INTERVAL_MIN=0)" "1"
ok "... reason batch"                                 "$(grep -c 'reason=batch$' "$GH_LOG" || true)" "1"

# 12 the window's CI_BATCH_MAX bypass counts EVERY first-parent merge since the last tested sha (T-10194 review): the
#    bisect caps at BISECT_MAX_MERGES first-parent merges, local and skip included, so 25 counted + 10 local must go
W="$T/max"; git init -q -b master "$W"; cd "$W"
git commit -q --allow-empty -m base; WB="$(git rev-parse HEAD)"
for i in $(seq 1 25); do git commit -q --allow-empty -m "counted $i"; done
for i in $(seq 1 6); do git commit -q --allow-empty -m "local $i" -m "Tests: local (npm test)"; done
W31="$(git rev-parse HEAD)"
for i in $(seq 7 10); do git commit -q --allow-empty -m "local $i" -m "Tests: local (npm test)"; done
{ runat success "$WB" batch-affected 2026-10-24T11:40:00Z; } | fixture
ok "25 counted + 10 local inside the window: one batch" "$(batch_push env GITHUB_SHA="$(git rev-parse HEAD)")" "1"
ok "... the summary counts 25 of 35"                   "$(grep -c '^master: 25 merge(s) to test.*(35 merged' "$T/out.txt" || true)" "1"
ok "25 counted + 6 local (31) inside the window: deferred" "$(batch_push env GITHUB_SHA="$W31")" "0"

# 12b the same cap makes a batch due on its own (T-10194 review 2): CI_BATCH_MAX merges of any choice waiting with at least
#    one counted. 22 local + 9 counted = 31 waits; the 32nd merge dispatches (9 counted, below CI_BATCH_SIZE), or the next
#    batch's range would run past what the bisect walks. 32 local merges: nothing to test, no batch.
V="$T/cap"; git init -q -b master "$V"; cd "$V"
git commit -q --allow-empty -m base; VB="$(git rev-parse HEAD)"
for i in $(seq 1 22); do git commit -q --allow-empty -m "local $i" -m "Tests: local (npm test)"; done
for i in $(seq 1 9); do git commit -q --allow-empty -m "counted $i"; done
V31="$(git rev-parse HEAD)"
git commit -q --allow-empty -m "local 23" -m "Tests: local (npm test)"; V32="$(git rev-parse HEAD)"
{ runat success "$VB" batch-affected 2026-10-24T11:40:00Z; } | fixture
ok "9 counted + 22 local (31) inside the window: nothing" "$(batch_push env GITHUB_SHA="$V31")" "0"
ok "... the 32nd merge (9 counted) dispatches the batch"  "$(batch_push env GITHUB_SHA="$V32")" "1"
ok "... AFFECTED from the baseline"                       "$(grep -c "reason=batch-affected.*base=$VB\$" "$GH_LOG" || true)" "1"
ok "... also with the window off"                         "$(batch_push env CI_BATCH_MIN_INTERVAL_MIN=0 GITHUB_SHA="$V32")" "1"
ok "CI_BATCH_MAX 33: the 32nd merge waits"                "$(batch_push env CI_BATCH_MAX=33 GITHUB_SHA="$V32")" "0"
V0="$T/cap0"; git init -q -b master "$V0"; cd "$V0"
git commit -q --allow-empty -m base; V0B="$(git rev-parse HEAD)"
for i in $(seq 1 32); do git commit -q --allow-empty -m "local $i" -m "Tests: local (npm test)"; done
{ runat success "$V0B" batch-affected 2026-10-24T11:40:00Z; } | fixture
ok "32 local merges, none counted: no batch"              "$(batch_push env GITHUB_SHA="$(git rev-parse HEAD)")" "0"

# 13 a master merge whose merged side is on dev counts toward no master batch only when it holds EXACTLY that side's
#    tree (T-10194 review): a promotion with a conflict fix of its own, or a hotfix branch merged into dev first and
#    then into a master that moved, holds code no dev batch tested
Q="$T/tree"; git init -q -b master "$Q"; cd "$Q"
echo a > a.txt; git add a.txt; git commit -q -m base; QB="$(git rev-parse HEAD)"
git checkout -q -b dev; echo b >> a.txt; git commit -q -am "dev change"; git update-ref refs/remotes/origin/dev HEAD
git checkout -q master; git merge -q --no-ff dev -m "Merge pull request #1 from tapperai/dev"; CLEAN="$(git rev-parse HEAD)"
{ run success 9 "$QB" batch; } | fixture
ok "a promotion of dev's exact tree: nothing counted"  "$(batch_push env GITHUB_SHA="$CLEAN" CI_BATCH_SIZE=1 CI_BATCH_MIN_INTERVAL_MIN=0)" "0"
git checkout -q -b m2 "$QB"; git merge -q --no-ff --no-commit dev >/dev/null 2>&1; echo fix > fix.txt; git add fix.txt
git commit -q -m "Merge pull request #2 from tapperai/dev"; FIXED="$(git rev-parse HEAD)"
ok "a promotion with a conflict fix of its own: counted" "$(batch_push env GITHUB_SHA="$FIXED" CI_BATCH_SIZE=1 CI_BATCH_MIN_INTERVAL_MIN=0)" "1"
ok "... the summary counts it"                         "$(grep -c '^master: 1 merge(s) to test' "$T/out.txt" || true)" "1"
git checkout -q -b hot "$QB"; echo h > h.txt; git add h.txt; git commit -q -m "hotfix"
git checkout -q dev; git merge -q --no-ff hot -m "Merge pull request #3 from tapperai/hot"; git update-ref refs/remotes/origin/dev HEAD
git checkout -q -b m3 "$QB"; echo m > m.txt; git add m.txt; git commit -q -m "master-only change" -m "Tests: local (npm test)"
git merge -q --no-ff hot -m "Merge pull request #4 from tapperai/hot"; HOTM="$(git rev-parse HEAD)"
ok "a hotfix merged into dev first, then into a moved master: counted" "$(batch_push env GITHUB_SHA="$HOTM" CI_BATCH_SIZE=1 CI_BATCH_MIN_INTERVAL_MIN=0)" "1"
# 13b a hotfix branch merged into dev first and then into an UNMOVED master has exactly its own tree (T-10194 review 2):
#    only a merged side on dev's FIRST-PARENT line (a dev tip, as a promotion carries) is dev-counted
git checkout -q master; git checkout -q -b hot2 "$CLEAN"; echo h2 > h2.txt; git add h2.txt; git commit -q -m "hotfix 2"
git checkout -q dev; git merge -q --no-ff hot2 -m "Merge pull request #5 from tapperai/hot2"; git update-ref refs/remotes/origin/dev HEAD
git checkout -q master; git merge -q --no-ff hot2 -m "Merge pull request #6 from tapperai/hot2"; HOT2M="$(git rev-parse HEAD)"
ok "the hotfix merge has exactly the hotfix's tree"    "$([ "$(git rev-parse "$HOT2M^{tree}")" = "$(git rev-parse hot2^{tree})" ] && echo same)" "same"
{ run success 9 "$CLEAN" batch; } | fixture
ok "... merged into dev first, into an unmoved master: counted" "$(batch_push env GITHUB_SHA="$HOT2M" CI_BATCH_SIZE=1 CI_BATCH_MIN_INTERVAL_MIN=0)" "1"
ok "... the summary counts it"                         "$(grep -c '^master: 1 merge(s) to test' "$T/out.txt" || true)" "1"
git checkout -q -b prom "$CLEAN"; git merge -q --no-ff dev -m "Merge pull request #7 from tapperai/dev"; PROM="$(git rev-parse HEAD)"; git checkout -q master
ok "a promotion of dev's tip (a first-parent commit) is still not counted" "$(batch_push env GITHUB_SHA="$PROM" CI_BATCH_SIZE=1 CI_BATCH_MIN_INTERVAL_MIN=0)" "0"

# 14 only the LEADING `Tests <sha>` of a run-name is the sha it tested (T-10194 review): a sha named in a free-text
#    reason is not a tested sha, and not the baseline of the push it names
{ run success 9 "$S1" "rerun, compare $S2"; run success 9 "$S3" batch; } | fixture
ok "a sha in the reason is not a tested sha"           "$(TRIGGER_SELFTEST=1 bash "$SCRIPT" tested_shas master | tr '\n' ' ')" "$S1 $S3 "
{ run success 9 "$(git rev-parse hot)" "on-demand, see $FIXED"; run success 9 "$QB" batch; } | fixture
ok "... nor the baseline of the commit it names"       "$(TRIGGER_SELFTEST=1 bash "$SCRIPT" last_tested_on_line master "$FIXED")" "$QB"

# 15 the baseline and the base are on the branch's FIRST-PARENT line (T-10194 review): an ancestor on a merged side (a
#    PR head merged with --no-ff, a dev commit a promotion carried) is not where the branch's own merges start
{ run success 9 "$(git rev-parse hot)" batch; run success 9 "$QB" batch; } | fixture
ok "an ancestor on a merged side is not on the line"   "$(TRIGGER_SELFTEST=1 bash "$SCRIPT" last_tested_on_line master "$HOTM")" "$QB"
batch_push env GITHUB_SHA="$HOTM" CI_BATCH_SIZE=1 CI_BATCH_MIN_INTERVAL_MIN=0 >/dev/null
ok "... nor the AFFECTED base"                         "$(grep -c "base=$QB\$" "$GH_LOG" || true)" "1"

# 16 batch-bisect.sh and the workflow that runs it (T-10194 review 2): a red batch-affected run is bisected from its own
#    base (tests.yml passes it as GOOD), the cap the trigger bypasses at is the cap the bisect uses, and with no green
#    end the bisect walks BISECT_MAX_MERGES merges, not CI_BATCH_SIZE
BIS="$(dirname "$SCRIPT")/batch-bisect.sh"; WFD="$(cd "$(dirname "$SCRIPT")/../../workflows" && pwd)"
B="$T/bis"; git init -q -b master "$B"; cd "$B"
for i in $(seq 1 40); do
  if [ "$i" = 15 ]; then echo bad > bad.txt; git add bad.txt; git commit -q -m "m$i (the culprit)"; else git commit -q --allow-empty -m "m$i"; fi
done
m() { git rev-parse "master~$((40 - $1))"; }   # m 1 = first commit, m 40 = head; m 15 adds the failure
mkdir -p "$T/rt"
# bisect [env...]: runs batch-bisect.sh at m40 with a step that fails once bad.txt exists; prints status, culprit, good
bisect() {
  rm -f "$B/bisect-result.json"
  env RUNNER_TEMP="$T/rt" BRANCH=master BAD="$(m 40)" BISECT_CMD='test ! -e bad.txt' BISECT_OUT="$B/bisect-result.json" \
    BISECT_MAX_MERGES=32 "$@" bash "$BIS" >"$T/bis.out" 2>&1 || true
  git bisect reset -q >/dev/null 2>&1 || true; git checkout -q master 2>/dev/null || true
  jq -r '[.status, .culprit_sha, .good] | @tsv' "$B/bisect-result.json"
}
TAB=$'\t'
echo '[]' > "$FIXTURE"
ok "no green end: the newest 32 merges are bisected, the culprit named"  "$(bisect | cut -f1,2)" "CULPRIT$TAB$(m 15)"
ok "... the good end is 32 merges back"                "$(bisect | cut -f3)" "$(m 8)"
ok "GOOD (a sha) is the good end"                      "$(bisect GOOD="$(m 10)" | cut -f1,2,3)" "CULPRIT$TAB$(m 15)$TAB$(m 10)"
ok "GOOD that is not a full sha is ignored"            "$(bisect GOOD=HEAD~30 | cut -f3)" "$(m 8)"
ok "GOOD that is an option is ignored"                 "$(bisect GOOD=--all | cut -f1,3)" "CULPRIT$TAB$(m 8)"
# the default good end is the newest green batch, batch-affected or nightly run (the trigger's family), not any green run
{ run success 9 "$(m 20)" affected; run success 9 "$(m 17)" on-demand; run success 9 "$(m 12)" batch-affected; run success 9 "$(m 9)" nightly; } | fixture
ok "the default good end skips affected and on-demand runs" "$(bisect | cut -f1,3)" "CULPRIT$TAB$(m 12)"
ok "a red nightly takes only a FULL run as the good end"    "$(bisect GOOD_FULL_ONLY=1 | cut -f1,3)" "CULPRIT$TAB$(m 9)"
# the workflow: a batch-affected run hands its base to the bisect, and the bisect's cap is the trigger's bypass cap
ok "tests.yml passes the batch-affected base as GOOD"  "$(grep -cF "GOOD: \${{ inputs.reason == 'batch-affected' && inputs.base || '' }}" "$WFD/tests.yml" || true)" "1"
trig_max="$(sed -nE 's/^MAXB="\$\{CI_BATCH_MAX:-([0-9]+)\}".*/\1/p' "$SCRIPT")"
bis_cap="$(grep -oE 'BISECT_MAX_MERGES: *"[0-9]+"' "$WFD/tests.yml" | grep -oE '[0-9]+' | head -1 || true)"
wf_max="$(grep -E "CI_BATCH_MAX: " "$WFD/test-batch.yml" | grep -oE "[0-9]+'" | tr -d "'" | head -1 || true)"
ok "tests.yml sets the bisect's BISECT_MAX_MERGES to CI_BATCH_MAX" "$bis_cap" "$trig_max"
ok "test-batch.yml's CI_BATCH_MAX default is the script's"        "$wf_max" "$trig_max"

echo "batch-trigger tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
