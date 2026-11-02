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
eq "two separate calls, pass removes needs-human-review" $'gh pr edit 7 --remove-label P --remove-label W --remove-label F\ngh pr edit 7 --add-label P --remove-label NHR' "$(cat "$GH_STUB_LOG")"
: > "$GH_STUB_LOG"
"$s/set-verdict-label.sh" 7 warning P W F NHR >/dev/null
eq "warning keeps needs-human-review" "gh pr edit 7 --add-label W" "$(tail -1 "$GH_STUB_LOG")"
if "$s/set-verdict-label.sh" 7 maybe P W F 2>/dev/null; then fail "unknown verdict → exit 1"; else pass "unknown verdict → exit 1"; fi

echo "# ensure-labels.sh"
: > "$GH_STUB_LOG"
GH_STUB_LABELS=$'pass\nbug' "$s/ensure-labels.sh" pass=0E8A16 fail=B60205 >/dev/null
eq "only missing labels created, never --force" $'gh label list --limit 1000 --json name --jq .[].name\ngh label create fail --color B60205' "$(cat "$GH_STUB_LOG")"
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
export PATUFET_CI_POLL_SECONDS=0
wait_ci() {  # wait_ci <names> <timeout-minutes>: prints the state line
  : > "$GH_STUB_LOG"
  "$s/wait-for-ci.sh" octo/app abc123 "$1" "$2" "$work/ci.json" 2> "$work/ci.err"
}
ci_state() { jq -r --arg n "$1" '.checks[] | select(.name == $n) | .state' "$work/ci.json"; }
export GH_STUB_CHECK_RUNS="$fx/check-runs-running.json:$fx/check-runs-failed.json"
eq "polls until every listed check has finished" "state=success" "$(wait_ci 'Frontend Build, test (ubuntu, 21)' 5)"
eq "... on the second poll" 2 "$(grep -c check-runs "$GH_STUB_LOG")"
eq "skipped counts as passed" success "$(ci_state 'Frontend Build')"
eq "a comma inside parentheses belongs to the name" success "$(ci_state 'test (ubuntu, 21)')"
eq "the review's own check is not waited for" 2 "$(jq '.checks | length' "$work/ci.json")"
eq "two lines are two names" "state=success" "$(wait_ci $'Frontend Build\ntest (ubuntu, 21)' 5)"
eq "with several lines, a comma stays in the name" "state=success" "$(wait_ci $'Lint, style\nFrontend Build\n' 5)"
eq "... and it is one check" 2 "$(jq '.checks | length' "$work/ci.json")"
eq "a single line with a final newline keeps its comma" "state=success" "$(wait_ci $'Lint, style\n' 5)"
eq "... and it is one check" "Lint, style" "$(jq -r '.checks[].name' "$work/ci.json")"
eq "nested parentheses stay in the name" "state=success" "$(wait_ci 'Frontend Build, test (Node.js (20), ubuntu)' 5)"
eq "... and they are two checks" 2 "$(jq '.checks | length' "$work/ci.json")"
eq "an unmatched parenthesis stays in the name" "state=success" "$(wait_ci 'Build (debug' 5)"
eq "a failure among repeated names wins" "state=failure" "$(wait_ci 'Backend Tests' 5)"
eq "job id from the details URL" 201 "$(jq -r '.checks[0].job_id' "$work/ci.json")"
eq "timed_out is a failure; external CI has no job id" "state=failure" "$(wait_ci 'External CI' 5)"
eq "external CI has no job id" null "$(jq -r '.checks[0].job_id' "$work/ci.json")"
export GH_STUB_CHECK_RUNS="$fx/check-runs-running.json"
eq "still running at the deadline" "state=timeout" "$(wait_ci 'Backend Tests' 0)"
eq "a name never seen also ends in timeout" "state=timeout" "$(wait_ci 'Bakend Tests' 0)"
has "... and the log names the checks seen" "Backend Tests, review" "$(cat "$work/ci.err")"
export GH_STUB_CHECK_RUNS="$fx/check-runs-failed.json"
eq "a failure wins over a pending check at the deadline" "state=failure" "$(wait_ci 'Backend Tests, review' 0)"
eq "... the pending one is reported as such" pending "$(ci_state review)"
eq "missing permission: no wait until the deadline" "state=unavailable" "$(GH_STUB_CHECK_RUNS_ERROR='gh: Resource not accessible by integration (HTTP 403)' wait_ci 'Backend Tests' 30)"
eq "... after a single call" 1 "$(grep -c check-runs "$GH_STUB_LOG")"
eq "transient errors are retried, then give up" "state=unavailable" "$(GH_STUB_CHECK_RUNS_ERROR='gh: HTTP 502' wait_ci 'Backend Tests' 30)"
eq "... after five calls" 5 "$(grep -c check-runs "$GH_STUB_LOG")"
unset PATUFET_CI_POLL_SECONDS GH_STUB_CHECK_RUNS

echo "# ci-section.sh"
result() {  # result <state> <checks json>
  jq -n --arg state "$1" --argjson checks "$2" '{state: $state, sha: "abc123", checks: $checks, seen: []}' > "$work/r.json"
}
failed='[{"name":"Backend Tests","state":"failure","conclusion":"failure","url":"https://x/job/201","job_id":"201"},{"name":"External CI","state":"failure","conclusion":"timed_out","url":"https://ci/9","job_id":null},{"name":"Frontend Build","state":"success","conclusion":"success","url":"https://x/job/202","job_id":"202"}]'
eq "no ci-checks: only the diff" "You cannot run tests or builds; base your assessment of tests on reading the diff only." "$("$s/ci-section.sh" octo/app "$work/none.json")"
result success '[{"name":"Backend Tests","state":"success"}]'
out=$("$s/ci-section.sh" octo/app "$work/r.json")
has "success names the checks" 'these checks passed: `Backend Tests`' "$out"
result timeout '[{"name":"Backend Tests","state":"pending"},{"name":"Testz","state":"missing"},{"name":"Lint","state":"success"}]'
out=$("$s/ci-section.sh" octo/app "$work/r.json")
has "timeout says CI could not be confirmed" "CI could not be confirmed" "$out"
has "timeout: a pending check is still running" '`Backend Tests`: still running' "$out"
has "timeout: a missing check is not said to be running" '`Testz`: no check with this name exists' "$out"
has "timeout: a finished check keeps its state" '`Lint`: success' "$out"
result unavailable '[{"name":"Backend Tests","state":"unknown"}]'
has "unavailable hints at the permission" "checks: read" "$("$s/ci-section.sh" octo/app "$work/r.json")"
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
has "e2e.yml uses the comment script" 'scripts/e2e-pass-comment.sh" "$PR_NUMBER" "$TESTED_SHA" "$LABEL_PASS" "$REVIEWER"' "$wf_e2e"
lacks "e2e.yml has no other ready-for-merge path" "Ready for human review" "$wf_e2e"
has "a forced fail mentions the reviewer" 'by hand to continue.$mention"' "$(cat "$root/.github/workflows/review.yml")"

echo "# detect-ci-checks.sh"
ci="$work/ci-repo"
mkdir -p "$ci/.github/workflows"
cat > "$ci/.github/workflows/ci.yml" <<'YAML'
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  backend:
    name: Backend Tests   # a comment
    runs-on: ubuntu-latest
    steps:
      - name: Not a job name
        uses: actions/checkout@v6
  frontend:
    runs-on: ubuntu-latest
    steps:
      - run: yarn generate
  matrix:
    name: test
    strategy:
      matrix:
        os: [a, b]
    runs-on: ${{ matrix.os }}
  shared:
    uses: ./.github/workflows/shared.yml
YAML
printf 'on: [push, pull_request]\njobs:\n    "lint":\n        name: "Lint #1" # a comment\n        runs-on: x\n' > "$ci/.github/workflows/lint.yaml"
printf 'on: [pull_request]\njobs:\n  style:\n    name: Lint, style\n  sized:\n    name: "test (ubuntu, 21)"\n  plain:\n    name: Unquoted #comment\n' > "$ci/.github/workflows/style.yml"
printf 'on:\n  push:\n    branches: [main]\njobs:\n  deploy:\n    name: Deploy\n' > "$ci/.github/workflows/deploy.yml"
printf 'on:\n  pull_request_target:\njobs:\n  label:\n    name: Label\n' > "$ci/.github/workflows/labeler.yml"
printf 'on:\n  pull_request:\njobs:\n  review:\n    name: Own\n' > "$ci/.github/workflows/patufet.yml"
printf 'on:\n  pull_request:\njobs:\n  review:\n    name: Theirs\n    steps:\n      - uses: anthropics/claude-code-action@v1\n' > "$ci/.github/workflows/claude.yml"
cat > "$ci/.github/workflows/odd.yml" <<'YAML'
on: pull_request
jobs:
  doubled:
    name: 'Bob''s tests'
  escaped:
    name: "say \"hi\""
  block:
    name: >-
      Integration tests
  alias:
    name: *shared
  unbalanced:
    name: Build (debug
  nested:
    name: test (Node.js (20), ubuntu)
  closing:
    name: a) b
  continued:
    name: two
      lines
  empty:
    name:
YAML
out=$(cd "$ci" && "$s/detect-ci-checks.sh")
for job in doubled escaped block alias unbalanced closing continued empty; do
  has "not read with certainty, so listed by hand: $job" $'dynamic\t.github/workflows/odd.yml: '"$job" "$out"
done
has "nested parentheses fit the list" $'check\ttest (Node.js (20), ubuntu)' "$out"
for wrong in Bob 'say' '>-' '*shared' 'Build (debug' 'a) b' 'two'; do lacks "not written as a check: $wrong" $'check\t'"$wrong" "$out"; done
has "job name" $'check\tBackend Tests' "$out"
has "job id when it has no name" $'check\tfrontend' "$out"
has "other indentation, # in a quoted name, inline trigger" $'check\tLint #1' "$out"
has "a comma outside parentheses cannot be listed" $'dynamic\t.github/workflows/style.yml: style' "$out"
has "a comma inside parentheses can" $'check\ttest (ubuntu, 21)' "$out"
eq "an unquoted name ends at its comment" $'check\tUnquoted' "$(grep -F Unquoted <<< "$out")"
has "matrix is dynamic" $'dynamic\t.github/workflows/ci.yml: matrix' "$out"
has "reusable workflow is dynamic" $'dynamic\t.github/workflows/ci.yml: shared' "$out"
for no in "Not a job name" Deploy Label Own Theirs; do lacks "not a PR check: $no" "$no" "$out"; done

echo "# permissions of the review job"
wf_review="$root/.github/workflows/review.yml"
eq "review.yml declares no permissions (a caller without actions: read would stop starting)" "" "$(grep -E '^ *permissions:' "$wf_review")"
caller_review=$(awk '/^  review:/{f=1;next} /^  [a-z0-9-]+:$/{f=0} f' "$root/templates/.github/workflows/patufet.yml")
for perm in "contents: read" "pull-requests: write" "issues: read" "id-token: write" "actions: read" "checks: read"; do
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
  [ "$(grep -c 'human-reviewer: "ana"' "$caller")" = 3 ] && echo "ok   reviewer filled in (review, fix-review and e2e)" || echo "FAIL reviewer filled in"
  grep -q 'ci-checks: ""$' "$caller" && echo "ok   no CI: ci-checks stays empty" || echo "FAIL no CI: ci-checks stays empty"
  grep -q 'no workflow runs CI on pull requests' "$work/b1.log" && echo "ok   no CI: warned" || echo "FAIL no CI: warned"
  grep -q 'secrets: inherit' "$caller" .github/workflows/patufet-mention.yml && echo "FAIL only the Claude secrets are passed" || echo "ok   only the Claude secrets are passed"
  [ "$(grep -c 'language: "ca"$' "$caller")" = 4 ] && echo "ok   language filled in" || echo "FAIL language filled in"
  grep -q 'e2e.yml@v1$' "$caller" && echo "ok   e2e job installed" || echo "FAIL e2e job installed"
  [ -f .github/patufet/e2e-up.sh ] && echo "ok   e2e hooks copied" || echo "FAIL e2e hooks copied"
  grep -q 'label create pass' "$GH_STUB_LOG" && echo "FAIL existing label recreated" || echo "ok   existing label left untouched"
  [ "$(grep -c 'label create' "$GH_STUB_LOG")" = 7 ] && echo "ok   7 missing labels created" || echo "FAIL 7 missing labels created"
  # the owner edits the caller, then re-runs the bootstrap with other options
  sed -i 's|ci-checks: ""|ci-checks: "mine"|' "$caller"
  before=$(cat .github/workflows/*.yml .github/patufet/* | md5sum)
  "$s/bootstrap.sh" --reviewer bob --language en --ref v9 > "$work/b2.log" 2>&1 || echo "FAIL bootstrap re-run exited non-zero: $(cat "$work/b2.log")"
  [ "$(cat .github/workflows/*.yml .github/patufet/* | md5sum)" = "$before" ] \
    && echo "ok   re-run modifies no existing file (e2e job, ci-checks, ref kept)" \
    || echo "FAIL re-run modifies no existing file"
  rm -rf .github .claude
  mkdir -p .github/workflows
  cp "$ci/.github/workflows/ci.yml" "$ci/.github/workflows/lint.yaml" .github/workflows/
  "$s/bootstrap.sh" --reviewer ana > "$work/b3.log" 2>&1 || echo "FAIL bootstrap with CI exited non-zero: $(cat "$work/b3.log")"
  grep -qxF '      ci-checks: "Backend Tests, frontend, Lint #1"' "$caller" \
    && echo "ok   detected CI jobs written to ci-checks" || echo "FAIL detected CI jobs written to ci-checks: $(grep ci-checks: "$caller")"
  grep -q 'ci.yml: matrix' "$work/b3.log" && echo "ok   jobs with a run-time name warned about" || echo "FAIL jobs with a run-time name warned about"
  grep -q 'no workflow runs CI' "$work/b3.log" && echo "FAIL CI present: no warning" || echo "ok   CI present: no warning"
  rm -rf .github .claude
  "$s/bootstrap.sh" --reviewer ana --language 'Catalan: Valencian "x"' > /dev/null 2>&1 || echo "FAIL bootstrap with free-text language"
  grep -qxF '      language: "Catalan: Valencian \"x\""' .github/workflows/patufet.yml \
    && echo "ok   free-text language written as a YAML string" || echo "FAIL free-text language written as a YAML string"
) > "$work/bootstrap.out"
cat "$work/bootstrap.out"
failures=$((failures + $(grep -c '^FAIL' "$work/bootstrap.out")))

echo "# verdict labels and report format"
line_of() { grep -n -m1 -F -- "$1" "$wf_review" | cut -d: -f1; }
cleared=$(line_of 'name: Remove the previous verdict label'); reviewed=$(line_of 'name: Run Claude Code review')
if [ -n "$cleared" ] && [ "$cleared" -lt "$reviewed" ]; then pass "review.yml removes the verdict labels before Claude runs"; else fail "review.yml removes the verdict labels before Claude runs"; fi
lacks "the reviewer does not remove verdict labels" '--remove-label "{{label_pass}}"' "$(cat "$root/prompts/review.md")"
has "the reviewer adds one label" '--add-label "LABEL"' "$(cat "$root/prompts/review.md")"
has "e2e relabels in one call" '--remove-label "{{label_warning}}" --add-label "{{label_fail}}"' "$(cat "$root/prompts/e2e.md")"
has "a re-run of e2e removes the previous fail, so that fix-review starts again" 'if: github.run_attempt > 1' "$(cat "$root/.github/workflows/e2e.yml")"
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
