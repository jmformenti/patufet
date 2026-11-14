#!/usr/bin/env bash
# Offline tests of the helper scripts, the bootstrap and the consistency
# between prompts, workflows and docs. No network, no GitHub: `gh` is the stub
# in tests/stubs, answering from tests/fixtures.
#
# Usage: tests/run.sh
# shellcheck disable=SC2016  # expected texts with literal backticks and $, nothing to expand
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fx="$root/tests/fixtures"
s="$root/scripts"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export PATH="$root/tests/stubs:$PATH" GH_STUB_LOG="$work/gh.log"
failures=0

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
eq() {  # eq <name> <expected> <actual>
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1"; printf '     expected: %q\n     actual:   %q\n' "$2" "$3"; fi
}
has() {  # has <name> <needle> <haystack>
  if grep -qF -- "$2" <<< "$3"; then pass "$1"; else fail "$1"; printf '     missing: %s\n' "$2"; fi
}
lacks() {  # lacks <name> <needle> <haystack>
  if grep -qF -- "$2" <<< "$3"; then fail "$1"; printf '     unexpected: %s\n' "$2"; else pass "$1"; fi
}

# Output of read-verdict.sh, or "EXIT <code>" when it fails: an expected
# empty verdict must not pass because the script crashed.
rv() {
  local out rc
  out=$("$s/read-verdict.sh" "$@" 2>/dev/null); rc=$?
  if [ "$rc" -eq 0 ]; then printf '%s' "$out"; else printf 'EXIT %s' "$rc"; fi
}

echo "# read-verdict.sh"
export GH_STUB_ISSUE_COMMENTS="$fx/review-comments.json"
eq "structured output wins" warning "$(STRUCTURED='{"verdict":"warning","summary":"x"}' rv review octo/app 7 cycle=3)"
eq "fallback: report of this cycle" warning "$(STRUCTURED='' rv review octo/app 7 cycle=2)"
eq "fallback: an earlier cycle never counts" "" "$(STRUCTURED='' rv review octo/app 7 cycle=3)"
eq "fallback: cycle=1 does not match cycle=11" fail "$(STRUCTURED='' rv review octo/app 7 cycle=1)"
eq "fallback: untrusted authors ignored" "" "$(STRUCTURED='' rv review octo/app 7 cycle=3)"
eq "fallback: another marker kind ignored" "" "$(STRUCTURED='' rv review octo/app 7 cycle=4)"
eq "fallback: verdict must be exact" "" "$(STRUCTURED='' rv review octo/app 7 cycle=5)"
eq "e2e: report of this run" fail "$(STRUCTURED='' rv e2e octo/app 7 run=55.1)"
eq "e2e: another attempt never counts" "" "$(STRUCTURED='' rv e2e octo/app 7 run=55.2)"
eq "invalid structured verdict rejected" "" "$(STRUCTURED='{"verdict":"maybe"}' rv review octo/app 7 cycle=9)"
eq "multi-line verdict rejected" "" "$(STRUCTURED='{"verdict":"pass\ninvalid"}' rv review octo/app 7 cycle=9)"
eq "e2e has no warning verdict" "" "$(STRUCTURED='{"verdict":"warning"}' rv e2e octo/app 7 run=1.1)"

echo "# find-plan.sh / count-review-cycles.sh / find-review-report.sh"
export GH_STUB_ISSUE_COMMENTS="$fx/plan-comments.json"
eq "latest collaborator plan wins; strangers and bots ignored" $'<!-- patufet:plan -->\n## Plan v2' "$("$s/find-plan.sh" octo/app 3)"
lacks "a comment without the marker is not a plan" "old style plan" "$("$s/find-plan.sh" octo/app 3)"
export GH_STUB_ISSUE_COMMENTS="$fx/review-comments.json"
if "$s/find-plan.sh" octo/app 3 >/dev/null 2>&1; then fail "no trusted plan → exit 1"; else pass "no trusted plan → exit 1"; fi
eq "cycles count trusted reports with the exact marker only" 4 "$("$s/count-review-cycles.sh" octo/app 7)"
has "latest trusted report" "cycle=11 verdict=pass" "$("$s/find-review-report.sh" octo/app 7)"
jq '.[:8]' "$fx/review-comments.json" > "$work/e2e-last.json"
has "a failed e2e after the review is the report to fix" "patufet:e2e run=55.1 verdict=fail" "$(GH_STUB_ISSUE_COMMENTS="$work/e2e-last.json" "$s/find-review-report.sh" octo/app 7)"
eq "cycles still count review reports only" 3 "$(GH_STUB_ISSUE_COMMENTS="$work/e2e-last.json" "$s/count-review-cycles.sh" octo/app 7)"

echo "# find-inline-comments.sh"
export GH_STUB_PR_COMMENTS="$fx/inline-comments.json"
out=$("$s/find-inline-comments.sh" octo/app 7)
has "current trusted comment kept" "current problem" "$out"
lacks "outdated comment left out" "outdated problem" "$out"
lacks "untrusted comment left out" "rm -rf" "$out"

echo "# find-linked-issue.sh"
linked() {
  jq -n --arg body "$1" --arg branch "${2:-feature/x}" '{body: $body, headRefName: $branch}' > "$work/pr.json"
  GH_STUB_PR_VIEW="$work/pr.json" "$s/find-linked-issue.sh" octo/app 7 agent/issue- || printf 'EXIT %s' "$?"
}
eq "Closes #12" 12 "$(linked 'Closes #12')"
eq "closes: #12" 12 "$(linked 'This closes: #12')"
eq "double space" 12 "$(linked 'Resolves  #12')"
eq "same repository reference" 12 "$(linked 'Fixes octo/app#12')"
eq "other repository ignored" "" "$(linked 'Fixes other/lib#12')"
eq "first keyword wins" 12 "$(linked $'Closes #12\ncloses #13')"
eq "keyword inside a word ignored" "" "$(linked 'prefixes #12')"
eq "branch fallback" 42 "$(linked 'no keyword' agent/issue-42)"
eq "branch with another prefix" "" "$(linked 'no keyword' feat/42)"

echo "# set-verdict-label.sh"
: > "$GH_STUB_LOG"
"$s/set-verdict-label.sh" 7 pass P W F NHR >/dev/null
eq "one call, pass removes needs-human-review" "gh pr edit 7 --add-label P --remove-label W --remove-label F --remove-label NHR" "$(cat "$GH_STUB_LOG")"
: > "$GH_STUB_LOG"
"$s/set-verdict-label.sh" 7 warning P W F NHR >/dev/null
eq "warning keeps needs-human-review" "gh pr edit 7 --add-label W --remove-label P --remove-label F" "$(cat "$GH_STUB_LOG")"
: > "$GH_STUB_LOG"
"$s/set-verdict-label.sh" 7 fail P W F NHR true >/dev/null
eq "fail can add needs-human-review" "gh pr edit 7 --add-label F --remove-label P --remove-label W --add-label NHR" "$(cat "$GH_STUB_LOG")"
: > "$GH_STUB_LOG"
"$s/set-verdict-label.sh" 7 pass P W F >/dev/null
eq "without the needs-human-review label it is left alone" "gh pr edit 7 --add-label P --remove-label W --remove-label F" "$(cat "$GH_STUB_LOG")"
if "$s/set-verdict-label.sh" 7 maybe P W F 2>/dev/null; then fail "unknown verdict → exit 1"; else pass "unknown verdict → exit 1"; fi

echo "# route-review.sh"
route() { "$s/route-review.sh" "$@" 2>/dev/null | tr '\n' ' ' || printf 'EXIT %s' "$?"; }
eq "pass → e2e" "verdict=pass next-stage=e2e needs-human=false reason=ok " "$(route pass success false false)"
eq "warning → fix-review" "verdict=warning next-stage=fix-review needs-human=false reason=ok " "$(route warning "" false false)"
eq "fail → fix-review" "verdict=fail next-stage=fix-review needs-human=false reason=ok " "$(route fail failure false false)"
eq "pass on a red CI → fail, a person decides" "verdict=fail next-stage= needs-human=true reason=forced-fail " "$(route pass failure false false)"
eq "CI failure unrelated to the diff → no fix" "verdict=fail next-stage= needs-human=true reason=human " "$(route fail failure true false)"
eq "no verdict → needs a human, no label" "verdict= next-stage= needs-human=true reason=no-verdict " "$(route "" "" false false)"
eq "PR moved on → no state at all" "verdict= next-stage= needs-human=false reason=moved " "$(route fail failure true true)"
eq "PR moved on wins over no verdict" "verdict= next-stage= needs-human=false reason=moved " "$(route "" "" false true)"
eq "pass on a timed-out CI still goes on" "verdict=pass next-stage=e2e needs-human=false reason=ok " "$(route pass timeout false false)"
eq "unknown verdict → error" "EXIT 1" "$(route maybe "" false false)"

echo "# ensure-labels.sh"
: > "$GH_STUB_LOG"
GH_STUB_LABELS=$'pass\nbug' "$s/ensure-labels.sh" pass=0E8A16 fail=B60205 >/dev/null
eq "only missing labels created, never --force" $'gh label list --limit 1000 --json name --jq .[].name\ngh label create fail --color B60205' "$(cat "$GH_STUB_LOG")"
: > "$GH_STUB_LOG"
GH_STUB_LABELS=$'Pass\nFAIL' "$s/ensure-labels.sh" pass=0E8A16 fail=B60205 >/dev/null
lacks "a label that differs only in case exists already" "label create" "$(cat "$GH_STUB_LOG")"
if GH_STUB_LABELS=pass GH_STUB_LABEL_CREATE_FAILS=1 "$s/ensure-labels.sh" pass=0E8A16 fail=B60205 >/dev/null; then fail "a label still missing → exit 1"; else pass "a label still missing → exit 1"; fi

echo "# render-prompt.sh"
printf 'A {{a}} B {{ missing }} C\n' > "$work/t.md"
printf 'Vue: {{ name }}\n' > "$work/ext.md"
out=$(TPL_a='{{b}}' "$s/render-prompt.sh" "$work/t.md" "$work/ext.md" 2> "$work/err")
has "values are not expanded again" "A {{b}} B" "$out"
has "unknown placeholder rendered empty" "B  C" "$out"
has "unknown placeholder reported" "placeholder {{missing}}" "$(cat "$work/err")"
has "extension appended verbatim" "Vue: {{ name }}" "$out"
: > "$work/empty.md"
lacks "empty extension adds no heading" "Project-specific" "$(TPL_a=x "$s/render-prompt.sh" "$work/t.md" "$work/empty.md" 2>/dev/null)"

echo "# plan-section.sh"
printf '## Plan\n' > "$work/plan.md"
has "review with plan" $'<plan>\n## Plan\n</plan>' "$("$s/plan-section.sh" review 5 "$work/plan.md")"
has "e2e without plan" "gh issue view 5" "$("$s/plan-section.sh" e2e 5 "$work/empty.md")"
has "no issue" "not linked to any issue" "$("$s/plan-section.sh" review "" "$work/empty.md")"

echo "# wait-for-ci.sh"
export PATUFET_CI_POLL_SECONDS=0 GH_STUB_JOBS_DIR="$fx/jobs"
wait_ci() {  # wait_ci <runs fixtures, colon-separated> <timeout-minutes>: prints the state line
  : > "$GH_STUB_LOG"
  GH_STUB_WORKFLOW_RUNS="$1" "$s/wait-for-ci.sh" octo/app abc123 .github/workflows/patufet.yml "$2" "$work/ci.json" 2> "$work/ci.err"
}
wf_state() { jq -r --arg n "$1" '.workflows[] | select(.name == $n) | .state' "$work/ci.json"; }
job_state() { jq -r --arg n "$1" '.checks[] | select(.name == $n) | .state' "$work/ci.json"; }
eq "polls until every workflow of the commit has finished" "state=failure" "$(wait_ci "$fx/runs-running.json:$fx/runs-failed.json" 5)"
eq "... on the second poll" 2 "$(grep -c 'actions/runs?' "$GH_STUB_LOG")"
has "... asking for the commit's pull_request runs" "actions/runs?head_sha=abc123&event=pull_request" "$(cat "$GH_STUB_LOG")"
eq "the caller's own workflow is not waited for" "" "$(wf_state patufet)"
eq "a run of another event is not CI of the PR" 2 "$(jq '.workflows | length' "$work/ci.json")"
eq "the latest run of a workflow wins" success "$(wf_state Lint)"
eq "the jobs are the checks" "failure success success" "$(jq -r '[.checks[].state] | join(" ")' "$work/ci.json")"
eq "a skipped job counts as passed" success "$(job_state 'Frontend Build')"
eq "a failed job carries its id, for its log" 201 "$(jq -r '.checks[] | select(.name == "Backend Tests") | .job_id' "$work/ci.json")"
eq "green" "state=success" "$(wait_ci "$fx/runs-green.json" 5)"
eq "a skipped workflow counts as passed" success "$(wf_state Lint)"
eq "nothing runs CI on the commit" "state=none" "$(wait_ci "$fx/runs-none.json" 5)"
eq "... after looking once more" 2 "$(grep -c 'actions/runs?' "$GH_STUB_LOG")"
eq "... and no job is reported" 0 "$(jq '.checks | length' "$work/ci.json")"
eq "a workflow that appears on the second look is waited for" "state=failure" "$(wait_ci "$fx/runs-none.json:$fx/runs-failed.json" 5)"
eq "still running at the deadline" "state=timeout" "$(wait_ci "$fx/runs-running.json" 0)"
eq "... reported as pending" pending "$(wf_state CI)"
eq "a failure wins over a pending workflow at the deadline" "state=failure" "$(wait_ci "$fx/runs-half.json" 0)"
eq "... the pending one is reported as such" pending "$(wf_state Lint)"
eq "jobs that cannot be read: the run stands for them" "state=failure" "$(wait_ci "$fx/runs-unreadable-jobs.json" 5)"
eq "... with its name and no job id" "Extra failure null" "$(jq -r '.checks[] | "\(.name) \(.state) \(.job_id)"' "$work/ci.json")"
eq "missing permission: no wait until the deadline" "state=unavailable" "$(GH_STUB_WORKFLOW_RUNS_ERROR='gh: Resource not accessible by integration (HTTP 403)' wait_ci x 30)"
eq "... after a single call" 1 "$(grep -c 'actions/runs?' "$GH_STUB_LOG")"
has "... and it names the permission" "actions: read" "$(cat "$work/ci.err")"
eq "transient errors are retried, then give up" "state=unavailable" "$(GH_STUB_WORKFLOW_RUNS_ERROR='gh: HTTP 502' wait_ci x 30)"
eq "... after five calls" 5 "$(grep -c 'actions/runs?' "$GH_STUB_LOG")"
unset PATUFET_CI_POLL_SECONDS GH_STUB_JOBS_DIR

echo "# ci-section.sh"
result() {  # result <state> <checks json>
  jq -n --arg state "$1" --argjson checks "$2" '{state: $state, sha: "abc123", checks: $checks, seen: []}' > "$work/r.json"
}
failed='[{"name":"Backend Tests","state":"failure","conclusion":"failure","url":"https://x/job/201","job_id":"201"},{"name":"External CI","state":"failure","conclusion":"timed_out","url":"https://ci/9","job_id":null},{"name":"Frontend Build","state":"success","conclusion":"success","url":"https://x/job/202","job_id":"202"}]'
eq "no wait (a fork PR): only the diff" "You cannot run tests or builds; base your assessment of tests on reading the diff only." "$("$s/ci-section.sh" octo/app "$work/none.json")"
result none '[]'
has "no CI on the commit is said" "no CI workflow ran on commit" "$("$s/ci-section.sh" octo/app "$work/r.json")"
result success '[{"name":"Backend Tests","state":"success"}]'
out=$("$s/ci-section.sh" octo/app "$work/r.json")
has "success names the jobs" 'these jobs passed: `Backend Tests`' "$out"
result success '[{"name":"Backend Tests","state":"success","conclusion":"success"},{"name":"Bot-skipped","state":"success","conclusion":"skipped"}]'
out=$("$s/ci-section.sh" octo/app "$work/r.json")
has "a skipped job is not said to have passed" 'these jobs passed: `Backend Tests`.' "$out"
has "... it is listed as skipped" 'skipped, so they tested nothing: `Bot-skipped`' "$out"
result success '[{"name":"Bot-skipped","state":"success","conclusion":"skipped"}]'
has "only skipped jobs: nothing ran" "no CI job actually ran" "$("$s/ci-section.sh" octo/app "$work/r.json")"
result timeout '[{"name":"Backend Tests","state":"pending"},{"name":"Lint","state":"success"}]'
out=$("$s/ci-section.sh" octo/app "$work/r.json")
has "timeout says CI could not be confirmed" "CI could not be confirmed" "$out"
has "timeout: a pending check is still running" '`Backend Tests`: still running' "$out"
has "timeout: a finished check keeps its state" '`Lint`: success' "$out"
result unavailable '[{"name":"Backend Tests","state":"unknown"}]'
has "unavailable hints at the permission" "actions: read" "$("$s/ci-section.sh" octo/app "$work/r.json")"
result failure "$failed"
export GH_STUB_JOB_LOG="$fx/job-log.txt"
: > "$GH_STUB_LOG"
out=$("$s/ci-section.sh" octo/app "$work/r.json")
has "failure is stated" "**CI failed**" "$out"
has "external check listed with its conclusion and URL" '`External CI`: timed_out (https://ci/9)' "$out"
has "log excerpt keeps the error" "FooTest.bar: expected 1 but was 2" "$out"
has "log excerpt ends at the last error" "##[error]Process completed" "$out"
lacks "the job's cleanup left out" "orphan processes" "$out"
lacks "timestamps stripped" "2026-11-01T" "$out"
eq "a log cannot close its own tag" 1 "$(grep -c '</ci-log>' <<< "$out")"
eq "only the failed Actions job is downloaded" "gh api repos/octo/app/actions/jobs/201/logs --allow-escape-sequences" "$(cat "$GH_STUB_LOG")"
has "a gh without the escape flag still gets the log" "FooTest.bar" "$(GH_STUB_OLD_GH=1 "$s/ci-section.sh" octo/app "$work/r.json")"
printf '2026-11-01T10:00:00.0000000Z \033[31mred error\033[0m\n' > "$work/colour.log"
out=$(GH_STUB_JOB_LOG="$work/colour.log" "$s/ci-section.sh" octo/app "$work/r.json")
has "colours removed" "red error" "$out"
lacks "no escape sequence reaches the prompt" $'\033' "$out"
out=$(GH_STUB_JOB_LOG_ERROR='gh: Resource not accessible by integration (HTTP 403)' "$s/ci-section.sh" octo/app "$work/r.json" 2>/dev/null)
has "no actions: read: failed names still reported" '`Backend Tests`: failure' "$out"
has "no actions: read: hint" "actions: read" "$out"
lacks "no actions: read: no log block" "<ci-log" "$out"
has "other log errors are said too" "could not be downloaded" "$(GH_STUB_JOB_LOG_ERROR='gh: HTTP 500' "$s/ci-section.sh" octo/app "$work/r.json")"
yes 'a very long line of build output that repeats and repeats and repeats' | head -5000 > "$work/big.log"
out=$(GH_STUB_JOB_LOG="$work/big.log" "$s/ci-section.sh" octo/app "$work/r.json")
if [ "${#out}" -lt 10000 ]; then pass "a long log without error lines is capped"; else fail "a long log without error lines is capped (${#out})"; fi
many=$(jq -nc '[range(5) | {name: "job\(.)", state: "failure", conclusion: "failure", url: "u", job_id: "\(.)"}]')
result failure "$many"
has "at most three logs" "Log of \`job3\` left out" "$("$s/ci-section.sh" octo/app "$work/r.json")"
unset GH_STUB_JOB_LOG

echo "# e2e-pass-comment.sh"
e2e_comment() {  # e2e_comment <head sha> <labels json> [reviewer]
  jq -n --arg head "$1" --argjson labels "$2" '{headRefOid: $head, labels: $labels}' > "$work/pr.json"
  GH_STUB_PR_VIEW="$work/pr.json" "$s/e2e-pass-comment.sh" 7 abcdef1234 pass "${3:-}"
}
out=$(e2e_comment abcdef1234 '[{"name":"bug"},{"name":"pass"}]' ana)
has "still pass, same commit: ready for merge" "Ready for human review and merge. @ana" "$out"
eq "no reviewer: no mention" "✅ patufet: code review and live e2e test passed. Ready for human review and merge." "$(e2e_comment abcdef1234 '[{"name":"pass"}]')"
out=$(e2e_comment abcdef1234 '[{"name":"fail"}]' ana)
has "verdict changed: not ready" "no longer labelled \`pass\`, so it is not ready for merge" "$out"
lacks "verdict changed: nobody mentioned" "@ana" "$out"
lacks "a label containing the name does not count" "Ready for" "$(e2e_comment abcdef1234 '[{"name":"bypass"}]')"
out=$(e2e_comment fedcba9876 '[{"name":"pass"}]' ana)
has "PR moved on: says so" "moved on to fedcba9" "$out"
lacks "PR moved on: nobody mentioned" "@ana" "$out"
wf_e2e=$(cat "$root/.github/workflows/e2e.yml")
lacks "e2e.yml has no other ready-for-merge path" "Ready for human review" "$wf_e2e"

# The scripts that set the state after a stage. Each case runs against a PR whose
# head is <head sha>; the gh calls land in $GH_STUB_LOG and the outputs in $work/out.
pr_at() { jq -n --arg head "$1" --argjson labels "${2:-[]}" '{headRefOid: $head, labels: $labels}' > "$work/pr.json"; }
calls() { grep -E "^gh (pr|label) (edit|comment|create)" "$GH_STUB_LOG" || true; }
outputs() { tr '\n' ' ' < "$work/out"; }

echo "# apply-review-verdict.sh"
arv() {  # arv <head sha> <structured> <ci state> [execution file]; prints "rc=<code>"
  pr_at "$1"; : > "$GH_STUB_LOG"; : > "$work/out"
  GITHUB_OUTPUT="$work/out" GH_STUB_PR_VIEW="$work/pr.json" GH_STUB_ISSUE_COMMENTS="$fx/review-comments.json" \
    STRUCTURED="$2" CI_STATE="$3" CLAUDE_EXECUTION_FILE="${4-$fx/execution.json}" HEAD_SHA=abcdef1234 \
    LABEL_PASS=P LABEL_WARNING=W LABEL_FAIL=F LABEL_NHR=NHR REVIEWER=ana RUN_URL=https://run \
    "$s/apply-review-verdict.sh" octo/app 7 9 > "$work/log" 2>&1
  echo "rc=$?"
}
eq "pass: succeeds" "rc=0" "$(arv abcdef1234 '{"verdict":"pass","summary":"x"}' success)"
eq "pass: labelled, needs-human-review removed" "gh pr edit 7 --add-label P --remove-label W --remove-label F --remove-label NHR" "$(calls)"
eq "pass: e2e follows" "verdict=pass next-stage=e2e needs-human=false reason=ok " "$(outputs)"
arv abcdef1234 '{"verdict":"warning","summary":"x"}' success > /dev/null
eq "warning: labelled, nobody told" "gh pr edit 7 --add-label W --remove-label P --remove-label F" "$(calls)"
eq "warning: fix-review follows" "verdict=warning next-stage=fix-review needs-human=false reason=ok " "$(outputs)"
arv abcdef1234 '{"verdict":"fail","summary":"x","needs_human":true}' failure > /dev/null
eq "CI failure unrelated to the diff: fail and needs-human-review" "gh pr edit 7 --add-label F --remove-label P --remove-label W --add-label NHR" "$(calls)"
eq "CI failure unrelated to the diff: no fix" "verdict=fail next-stage= needs-human=true reason=human " "$(outputs)"
eq "pass on a red CI: succeeds" "rc=0" "$(arv abcdef1234 '{"verdict":"pass","summary":"x"}' failure)"
eq "pass on a red CI: forced to fail, a person decides" "gh pr edit 7 --add-label F --remove-label P --remove-label W --add-label NHR" "$(calls | head -1)"
has "pass on a red CI: a comment says so" 'gh pr comment 7 --body ⚠️ patufet: the reviewer returned `pass` although CI failed, so the workflow set `F`.' "$(calls)"
has "pass on a red CI: the reviewer is mentioned" 'to let fix-review try. @ana' "$(cat "$GH_STUB_LOG")"
eq "pass on a red CI: nothing follows" "verdict=fail next-stage= needs-human=true reason=forced-fail " "$(outputs)"
eq "PR moved on: succeeds" "rc=0" "$(arv fedcba9876 '{"verdict":"fail","summary":"x"}' failure)"
eq "PR moved on: no label, no comment" "" "$(calls)"
eq "PR moved on: nothing follows" "verdict= next-stage= needs-human=false reason=moved " "$(outputs)"
eq "no verdict: the job fails" "rc=1" "$(arv abcdef1234 '' success)"
eq "no verdict: needs-human-review and a comment" $'gh pr edit 7 --add-label NHR\ngh pr comment 7 --body ⚠️ patufet: review cycle 9 produced no verdict. Manual review needed. See https://run' "$(calls)"
eq "no verdict: nothing follows" "verdict= next-stage= needs-human=true reason=no-verdict " "$(outputs)"
eq "the action did not run: the job fails" "rc=1" "$(arv abcdef1234 '{"verdict":"pass","summary":"x"}' success "")"
eq "the action did not run: no label, no comment, no output" "" "$(calls)$(outputs)"
has "the action did not run: says so" "::error::The Claude action did not finish" "$(cat "$work/log")"

echo "# apply-e2e-verdict.sh"
aev() {  # aev <head sha> <labels json> <structured> <claude outcome> [execution file]; prints "rc=<code>"
  pr_at "$1" "$2"; : > "$GH_STUB_LOG"; : > "$work/out"
  GITHUB_OUTPUT="$work/out" GH_STUB_PR_VIEW="$work/pr.json" GH_STUB_ISSUE_COMMENTS="$fx/review-comments.json" \
    STRUCTURED="$3" CLAUDE_OUTCOME="$4" CLAUDE_EXECUTION_FILE="${5-$fx/execution.json}" TESTED_SHA=abcdef1234 \
    LABEL_PASS=pass LABEL_WARNING=W LABEL_FAIL=F REVIEWER=ana RUN_URL=https://run \
    "$s/apply-e2e-verdict.sh" octo/app 7 "${RUN_KEY:-99.1}" > "$work/log" 2>&1
  echo "rc=$?"
}
eq "pass: succeeds" "rc=0" "$(aev abcdef1234 '[{"name":"pass"}]' '{"verdict":"pass","summary":"x"}' success)"
eq "pass: ready for merge, no label touched" "gh pr comment 7 --body ✅ patufet: code review and live e2e test passed. Ready for human review and merge. @ana" "$(calls)"
eq "pass: nothing follows" "verdict=pass " "$(outputs)"
aev fedcba9876 '[{"name":"pass"}]' '{"verdict":"pass","summary":"x"}' success > /dev/null
has "pass, PR moved on: not ready" "moved on to fedcba9" "$(calls)"
eq "fail: succeeds" "rc=0" "$(aev abcdef1234 '[{"name":"pass"}]' '{"verdict":"fail","summary":"x"}' success)"
eq "fail: labelled, no comment" "gh pr edit 7 --add-label F --remove-label pass --remove-label W" "$(calls)"
eq "fail: fix-review follows" "verdict=fail next-stage=fix-review " "$(outputs)"
eq "fail, PR moved on: succeeds" "rc=0" "$(aev fedcba9876 '[]' '{"verdict":"fail","summary":"x"}' success)"
eq "fail, PR moved on: no label" "" "$(calls)"
eq "fail, PR moved on: nothing follows" "verdict=fail " "$(outputs)"
RUN_KEY=55.1 aev abcdef1234 '[]' '' success > /dev/null
eq "no structured output: the report of this run counts" "verdict=fail next-stage=fix-review " "$(outputs)"
eq "no verdict: the job fails" "rc=1" "$(aev abcdef1234 '[]' '' success)"
eq "no verdict: a comment, no label" "gh pr comment 7 --body ⚠️ patufet: the live e2e run produced no verdict (outcome: success). Manual check needed. See https://run" "$(calls)"
eq "a failed Claude step: the job fails whatever it returned" "rc=1" "$(aev abcdef1234 '[]' '{"verdict":"pass","summary":"x"}' failure)"
lacks "a failed Claude step: not ready for merge" "Ready for" "$(calls)"
eq "the action did not run: the job fails" "rc=1" "$(aev abcdef1234 '[]' '{"verdict":"pass","summary":"x"}' success "")"
eq "the action did not run: no comment, no output" "" "$(calls)$(outputs)"

echo "# fix-gate.sh"
gate() {  # gate <before|after> <head sha> <count>; prints "rc=<code>"
  pr_at "$2"; : > "$GH_STUB_LOG"; : > "$work/out"
  GITHUB_OUTPUT="$work/out" GH_STUB_PR_VIEW="$work/pr.json" GH_STUB_LABELS="NHR" \
    STARTED_SHA=abcdef1234 COUNT="${3:-0}" MAX_CYCLES=10 LABEL_NHR=NHR REVIEWER=ana RUN_URL=https://run \
    "$s/fix-gate.sh" "$1" 7 > "$work/log" 2>&1
  echo "rc=$?"
}
eq "before: under the limit → fix" "rc=0 state=fix " "$(gate before abcdef1234 3) $(outputs)"
eq "before: under the limit → nothing labelled" "" "$(calls)"
eq "before: PR moved on → nothing to fix" "rc=0 state=moved " "$(gate before fedcba9876 3) $(outputs)"
eq "before: PR moved on wins over the limit" "rc=0 state=moved " "$(gate before fedcba9876 10) $(outputs)"
eq "before: PR moved on → nothing labelled" "" "$(calls)"
eq "before: at the limit → a person" "rc=0 state=limit " "$(gate before abcdef1234 10) $(outputs)"
eq "before: at the limit → needs-human-review and a mention" $'gh pr edit 7 --add-label NHR\ngh pr comment 7 --body ⚠️ patufet: 10 automatic review cycles reached without a `pass` verdict. Manual review needed. @ana' "$(calls)"
eq "after: the agent pushed → nothing to do" "rc=0" "$(gate after fedcba9876)"
eq "after: the agent pushed → nothing labelled" "" "$(calls)"
eq "after: nothing pushed → still a success" "rc=0" "$(gate after abcdef1234)"
eq "after: nothing pushed → needs-human-review and a mention" $'gh pr edit 7 --add-label NHR\ngh pr comment 7 --body ⚠️ patufet: fix-review ended without pushing a change, so no new review starts. Its comments on this PR, if any, say why. Manual review needed. See https://run @ana' "$(calls)"
pr_at abcdef1234; : > "$GH_STUB_LOG"
GH_STUB_PR_VIEW="$work/pr.json" GH_STUB_LABELS="" STARTED_SHA=abcdef1234 LABEL_NHR=NHR "$s/fix-gate.sh" after 7 > /dev/null 2>&1
has "after: a missing needs-human-review label is created first" "gh label create NHR --color 5319E7" "$(cat "$GH_STUB_LOG")"
lacks "after: no reviewer, no mention" "@" "$(calls)"
if STARTED_SHA=x LABEL_NHR=NHR GH_STUB_PR_VIEW="$work/pr.json" "$s/fix-gate.sh" maybe 7 > /dev/null 2>&1; then fail "unknown mode → error"; else pass "unknown mode → error"; fi

echo "# detect-pr-ci.sh"
ci="$work/ci-repo"
mkdir -p "$ci/.github/workflows"
printf 'name: CI\non:\n  push:\n    branches: [main]\n  pull_request:\njobs:\n  t:\n    runs-on: x\n' > "$ci/.github/workflows/ci.yml"
printf 'on: [push, pull_request] # inline\njobs:\n  l:\n    runs-on: x\n' > "$ci/.github/workflows/lint.yaml"
printf 'on:\n  push:\n    branches: [main]\njobs:\n  d:\n    runs-on: x\n' > "$ci/.github/workflows/deploy.yml"
printf 'on:\n  pull_request_target:\njobs:\n  l:\n    runs-on: x\n' > "$ci/.github/workflows/labeler.yml"
printf 'on:\n  pull_request_review:\njobs:\n  r:\n    runs-on: x\n' > "$ci/.github/workflows/on-review.yml"
printf 'on:\n  pull_request:\njobs:\n  review:\n    runs-on: x\n' > "$ci/.github/workflows/patufet.yml"
printf 'on:\n  pull_request:\njobs:\n  r:\n    steps:\n      - uses: anthropics/claude-code-action@v1\n' > "$ci/.github/workflows/claude.yml"
printf 'on:\n  workflow_dispatch:\njobs:\n  pull_request:\n    runs-on: x\n' > "$ci/.github/workflows/manual.yml"
out=$(cd "$ci" && "$s/detect-pr-ci.sh")
eq "only the workflows that run on pull requests" $'.github/workflows/ci.yml\n.github/workflows/lint.yaml' "$out"
empty="$work/no-ci-repo"; mkdir -p "$empty/.github/workflows"
cp "$ci/.github/workflows/deploy.yml" "$empty/.github/workflows/"
eq "none: empty output, still a success" "" "$(cd "$empty" && "$s/detect-pr-ci.sh")"

echo "# the review waits for the CI it finds (decision 12)"
has "review waits for the commit's CI, minus its own workflow" '"$TPL_DIR/scripts/wait-for-ci.sh" "$GITHUB_REPOSITORY" "$HEAD_SHA" "$own"' "$(cat "$root/.github/workflows/review.yml")"
has "the own workflow comes from the caller's ref" 'CALLER_REF: ${{ github.workflow_ref }}' "$(cat "$root/.github/workflows/review.yml")"

echo "# permissions of the review job"
wf_review="$root/.github/workflows/review.yml"
eq "review.yml declares no permissions (a caller without actions: read would stop starting)" "" "$(grep -E '^ *permissions:' "$wf_review")"
caller_review=$(awk '/^  review:/{f=1;next} /^  [a-z0-9-]+:$/{f=0} f' "$root/templates/.github/workflows/patufet.yml")
for perm in "contents: read" "pull-requests: write" "issues: read" "id-token: write" "actions: read"; do
  has "caller's review job grants $perm" "$perm" "$caller_review"
done

echo "# github-output.sh"
export GITHUB_OUTPUT="$work/out"
: > "$GITHUB_OUTPUT"
printf 'line 1\nPATUFET_PROMPT_EOF\nline 3' | "$s/github-output.sh" text
delim=$(head -1 "$GITHUB_OUTPUT" | sed 's/^text<<//')
eq "content survives a line that looks like a delimiter" $'line 1\nPATUFET_PROMPT_EOF\nline 3' "$(sed '1d;$d' "$GITHUB_OUTPUT")"
eq "delimiter closes the value" "$delim" "$(tail -1 "$GITHUB_OUTPUT")"
unset GITHUB_OUTPUT

echo "# run-summary.sh"
out=$(GITHUB_STEP_SUMMARY="" "$s/run-summary.sh" review "$fx/execution.json" "Verdict: pass")
has "turns" "| Turns | 42 |" "$out"
has "cost" "\$1.23" "$out"
has "duration" "12.5 min" "$out"
has "extra line" "| Verdict | pass |" "$out"
has "no execution file" "did not run" "$(GITHUB_STEP_SUMMARY="" "$s/run-summary.sh" review "")"

echo "# bootstrap.sh"
repo="$work/consumer"
git init -q "$repo"
mkdir -p "$repo/.github/workflows"
(
  cd "$repo" || exit 1
  export GH_STUB_LABELS="pass" GH_STUB_SECRETS="ANTHROPIC_API_KEY"
  : > "$GH_STUB_LOG"
  if "$s/bootstrap.sh" --reviewer --with-e2e > /dev/null 2>&1; then echo "FAIL an option is not accepted as a value"; else echo "ok   an option is not accepted as a value"; fi
  "$s/bootstrap.sh" --reviewer ana --language ca --with-e2e > "$work/b1.log" 2>&1 || echo "FAIL bootstrap exited non-zero: $(cat "$work/b1.log")"
  caller=.github/workflows/patufet.yml
  [ "$(grep -c 'human-reviewer: "ana"' "$caller")" = 4 ] && echo "ok   reviewer filled in (review, fix-review, e2e and fix-e2e)" || echo "FAIL reviewer filled in"
  grep -q 'no workflow runs CI on pull requests' "$work/b1.log" && echo "ok   no CI: warned" || echo "FAIL no CI: warned"
  secrets_passed=$(grep -E '^ +secrets: *inherit|\$\{\{ *secrets\.' "$caller" .github/workflows/patufet-mention.yml | grep -oE 'inherit|secrets\.[A-Za-z0-9_]+' | sort -u | tr '\n' ' ')
  [ "$secrets_passed" = "secrets.ANTHROPIC_API_KEY secrets.CLAUDE_CODE_OAUTH_TOKEN " ] && echo "ok   only the Claude secrets are passed" || echo "FAIL only the Claude secrets are passed: $secrets_passed"
  [ "$(grep -c 'language: "ca"$' "$caller")" = 5 ] && echo "ok   language filled in" || echo "FAIL language filled in"
  grep -q 'e2e.yml@v1$' "$caller" && echo "ok   e2e job installed" || echo "FAIL e2e job installed"
  [ -f .github/patufet/e2e-up.sh ] && echo "ok   e2e hooks copied" || echo "FAIL e2e hooks copied"
  grep -q 'label create pass' "$GH_STUB_LOG" && echo "FAIL existing label recreated" || echo "ok   existing label left untouched"
  [ "$(grep -c 'label create' "$GH_STUB_LOG")" = 7 ] && echo "ok   7 missing labels created" || echo "FAIL 7 missing labels created"
  # the owner edits the caller, then re-runs the bootstrap with other options
  sed -i 's|human-reviewer: "ana"|human-reviewer: "mine"|' "$caller"
  before=$(cat .github/workflows/*.yml .github/patufet/* | md5sum)
  "$s/bootstrap.sh" --reviewer bob --language en --ref v9 > "$work/b2.log" 2>&1 || echo "FAIL bootstrap re-run exited non-zero: $(cat "$work/b2.log")"
  [ "$(cat .github/workflows/*.yml .github/patufet/* | md5sum)" = "$before" ] \
    && echo "ok   re-run modifies no existing file (e2e job, owner's edit, ref kept)" \
    || echo "FAIL re-run modifies no existing file"
  rm -rf .github .claude
  mkdir -p .github/workflows
  cp "$ci/.github/workflows/ci.yml" "$ci/.github/workflows/lint.yaml" .github/workflows/
  "$s/bootstrap.sh" --reviewer ana > "$work/b3.log" 2>&1 || echo "FAIL bootstrap with CI exited non-zero: $(cat "$work/b3.log")"
  grep -q 'review will wait for: .github/workflows/ci.yml .github/workflows/lint.yaml' "$work/b3.log" \
    && echo "ok   CI present: the workflows the review waits for are named" || echo "FAIL CI present: the workflows the review waits for are named"
  grep -q 'no workflow runs CI' "$work/b3.log" && echo "FAIL CI present: no warning" || echo "ok   CI present: no warning"
  rm -rf .github .claude
  "$s/bootstrap.sh" --reviewer ana --language 'Catalan: Valencian "x"' > /dev/null 2>&1 || echo "FAIL bootstrap with free-text language"
  grep -qxF '      language: "Catalan: Valencian \"x\""' .github/workflows/patufet.yml \
    && echo "ok   free-text language written as a YAML string" || echo "FAIL free-text language written as a YAML string"
) > "$work/bootstrap.out"
cat "$work/bootstrap.out"
failures=$((failures + $(grep -c '^FAIL' "$work/bootstrap.out")))

echo "# verdict labels and the chaining of stages (decision 11)"
line_of() { grep -n -m1 -F -- "$1" "$wf_review" | cut -d: -f1; }
cleared=$(line_of 'name: Remove the previous verdict label'); reviewed=$(line_of 'name: Run Claude Code review')
if [ -n "$cleared" ] && [ "$cleared" -lt "$reviewed" ]; then pass "review.yml removes the verdict labels before Claude runs"; else fail "review.yml removes the verdict labels before Claude runs"; fi
for stage in review e2e; do
  lacks "$stage: the agent is not told to label" 'gh pr edit' "$(cat "$root/prompts/$stage.md")"
  lacks "$stage: the agent cannot label" 'Bash(gh pr edit' "$(cat "$root/.github/workflows/$stage.yml")"
  has "$stage: returns the next stage to the caller" 'value: ${{ jobs.'"$stage"'.outputs.next-stage }}' "$(cat "$root/.github/workflows/$stage.yml")"
done
has "review.yml applies the verdict with the script" 'scripts/apply-review-verdict.sh" "$GITHUB_REPOSITORY" "$PR_NUMBER" "$CYCLE"' "$(cat "$wf_review")"
has "the verdict script routes with route-review.sh" 'route-review.sh" "$verdict" "${CI_STATE:-}" "$needs_human" "$moved"' "$(cat "$s/apply-review-verdict.sh")"
has "e2e.yml applies the verdict with the script" 'scripts/apply-e2e-verdict.sh" "$GITHUB_REPOSITORY" "$PR_NUMBER" "$RUN_KEY"' "$wf_e2e"
has "the reviewer can ask for a human in the structured result" '"needs_human":{"type":"boolean"}' "$(cat "$wf_review")"
has "the prompt explains needs_human" '"needs_human": true' "$(cat "$root/prompts/review.md")"
has "a re-run of e2e restores pass" 'name: Restore the pass label on a re-run' "$wf_e2e"
wf_fix=$(cat "$root/.github/workflows/fix-review.yml")
has "fix-review decides with the gate" 'scripts/fix-gate.sh" before "$PR_NUMBER"' "$wf_fix"
has "fix-review checks that the agent pushed" 'scripts/fix-gate.sh" after "$PR_NUMBER"' "$wf_fix"
has "the hand-over also runs when a step before the agent failed" "if: \${{ !cancelled() && steps.gate.outputs.state == 'fix' }}" "$(awk '/name: Hand over to a human if nothing was pushed/{f=1} f&&/if:/{print;exit}' "$root/.github/workflows/fix-review.yml")"
has "the agent only runs when the gate says fix" "if: steps.gate.outputs.state == 'fix'" "$(awk '/id: claude/{f=1} f&&/if:/{print;exit}' "$root/.github/workflows/fix-review.yml")"
lacks "no stage asks a person to relabel to continue" 'by hand to continue' "$(cat "$root"/.github/workflows/*.yml "$s"/*.sh)"

echo "# the workflows themselves"
fetch_step() { awk '/- name: Fetch patufet template/{f=1} f&&/^        env:/{exit} f' "$root/.github/workflows/$1.yml"; }
for stage in review fix-review e2e; do
  eq "$stage: fetches the template like implement.yml" "$(fetch_step implement)" "$(fetch_step "$stage")"
done
has "the fetch step was found" 'tarball/$TEMPLATE_SHA' "$(fetch_step implement)"
lacks "e2e: the job's token does not reach the hooks of the PR" 'GH_TOKEN' "$(awk '/^    env:/{f=1;next} /^    steps:/{f=0} f' "$root/.github/workflows/e2e.yml")"
for step in 'Start the application (e2e-up hook)' 'Stop the application (e2e-down hook)'; do
  lacks "e2e: no token in '$step'" 'GH_TOKEN' "$(awk -v n="      - name: $step" '$0 == n {f=1; next} /^      - name:/{f=0} f' "$root/.github/workflows/e2e.yml")"
done
has "implement: the issue labels are ensured before the first one is set" 'scripts/ensure-labels.sh" "$LABEL_READY=' "$(sed '/name: Extract the approved plan/q' "$root/.github/workflows/implement.yml")"
caller_job() { awk -v j="  $1:" '$0 == j {f=1; next} /^  [a-z0-9-]+:$/ {f=0} f' "$root/templates/.github/workflows/patufet.yml"; }
for job in fix-review e2e; do
  has "caller: $job needs the review" 'needs: review' "$(caller_job "$job")"
  has "caller: $job also runs when the review is skipped (a person's label)" '!cancelled()' "$(caller_job "$job")"
done
has "caller: fix-review follows the review's next stage" "needs.review.outputs.next-stage == 'fix-review'" "$(caller_job fix-review)"
has "caller: e2e follows the review's next stage" "needs.review.outputs.next-stage == 'e2e'" "$(caller_job e2e)"
has "caller: fix-e2e follows a failed e2e" "needs.e2e.outputs.next-stage == 'fix-review'" "$(caller_job fix-e2e)"
e2e_block=$(sed -n '/# --- e2e (optional)/,/# --- end e2e ---/p' "$root/templates/.github/workflows/patufet.yml")
has "caller: fix-e2e is removed with the e2e block" '  fix-e2e:' "$e2e_block"
for stage in review e2e; do
  has "$stage: the report has no line starting with #" 'No line of this comment may start with `#`' "$(cat "$root/prompts/$stage.md")"
done

echo "# prompts ↔ workflows ↔ docs"
for stage in implement fix-review; do
  has "$stage: the agent reproduces CI" 'the steps of the CI workflows' "$(tr '\n' ' ' < "$root/prompts/$stage.md")"
done
for stage in implement review fix-review e2e; do
  wf="$root/.github/workflows/$stage.yml"
  for p in $(grep -oE '\{\{[a-z0-9_]+\}\}' "$root/prompts/$stage.md" | tr -d '{}' | sort -u); do
    if grep -qE "TPL_${p}[=:]" "$wf"; then pass "$stage: {{$p}} is set"; else fail "$stage: {{$p}} has no TPL_$p in $stage.yml"; fi
  done
done
literal=$(grep -nE -- '--(add|remove)-label [a-z]' "$root"/prompts/*.md || true)
eq "no hard-coded label names in prompts" "" "$literal"
docs=$(cat "$root/docs/customization.md" "$root/docs/e2e.md")
for wf in "$root"/.github/workflows/{implement,review,fix-review,e2e,mention}.yml; do
  while IFS= read -r input; do
    case "$input" in label-*) key="label-" ;; *) key="$input" ;; esac
    if grep -qF "\`$key" <<< "$docs"; then pass "$(basename "$wf" .yml): input $input documented"; else fail "$(basename "$wf" .yml): input $input missing from docs/customization.md or docs/e2e.md"; fi
  done < <(awk '/^    inputs:/{f=1;next} /^    (secrets|outputs):/{f=0} f && /^      [a-z0-9-]+:$/{gsub(/[ :]/,"");print}' "$wf")
done

echo
if [ "$failures" -eq 0 ]; then echo "All tests passed."; else echo "$failures test(s) failed."; exit 1; fi
