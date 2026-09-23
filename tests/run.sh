#!/usr/bin/env bash
# Offline tests of the helper scripts, the bootstrap and the consistency
# between prompts, workflows and docs. No network, no GitHub: `gh` is the stub
# in tests/stubs, answering from tests/fixtures.
#
# Usage: tests/run.sh
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

echo "# read-verdict.sh"
export GH_STUB_ISSUE_COMMENTS="$fx/review-comments.json"
eq "structured output wins" warning "$(STRUCTURED='{"verdict":"warning","summary":"x"}' "$s/read-verdict.sh" review octo/app 7 cycle=3)"
eq "fallback: report of this cycle" warning "$(STRUCTURED='' "$s/read-verdict.sh" review octo/app 7 cycle=2 2>/dev/null)"
eq "fallback: an earlier cycle never counts" "" "$(STRUCTURED='' "$s/read-verdict.sh" review octo/app 7 cycle=3 2>/dev/null)"
eq "fallback: cycle=1 does not match cycle=11" fail "$(STRUCTURED='' "$s/read-verdict.sh" review octo/app 7 cycle=1 2>/dev/null)"
eq "fallback: untrusted authors ignored" "" "$(STRUCTURED='' "$s/read-verdict.sh" review octo/app 7 cycle=3 2>/dev/null)"
eq "e2e: report of this run" fail "$(STRUCTURED='' "$s/read-verdict.sh" e2e octo/app 7 run=55.1 2>/dev/null)"
eq "e2e: another attempt never counts" "" "$(STRUCTURED='' "$s/read-verdict.sh" e2e octo/app 7 run=55.2 2>/dev/null)"
eq "invalid structured verdict rejected" "" "$(STRUCTURED='{"verdict":"maybe"}' "$s/read-verdict.sh" review octo/app 7 cycle=9 2>/dev/null)"
eq "e2e has no warning verdict" "" "$(STRUCTURED='{"verdict":"warning"}' "$s/read-verdict.sh" e2e octo/app 7 run=1.1 2>/dev/null)"

echo "# find-plan.sh / count-review-cycles.sh / find-review-report.sh"
export GH_STUB_ISSUE_COMMENTS="$fx/plan-comments.json"
eq "latest collaborator plan wins; strangers and bots ignored" $'<!-- patufet:plan -->\n## Plan v2' "$("$s/find-plan.sh" octo/app 3)"
has "legacy heading accepted when configured" "old style plan" "$("$s/find-plan.sh" octo/app 3 "## Pla d'implementació")"
export GH_STUB_ISSUE_COMMENTS="$fx/review-comments.json"
if "$s/find-plan.sh" octo/app 3 >/dev/null 2>&1; then fail "no trusted plan → exit 1"; else pass "no trusted plan → exit 1"; fi
eq "cycles count trusted reports only" 3 "$("$s/count-review-cycles.sh" octo/app 7)"
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
  GH_STUB_PR_VIEW="$work/pr.json" "$s/find-linked-issue.sh" octo/app 7 agent/issue-
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

echo "# plan-section.sh / format-test-command.sh"
printf '## Plan\n' > "$work/plan.md"
has "review with plan" $'<plan>\n## Plan\n</plan>' "$("$s/plan-section.sh" review 5 "$work/plan.md")"
has "e2e without plan" "gh issue view 5" "$("$s/plan-section.sh" e2e 5 "$work/empty.md")"
has "no issue" "not linked to any issue" "$("$s/plan-section.sh" review "" "$work/empty.md")"
eq "test command as a bash block" $'```bash\nmake test\n```' "$("$s/format-test-command.sh" 'make test')"
has "no test command" "No test command configured" "$("$s/format-test-command.sh" '')"

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
  "$s/bootstrap.sh" --reviewer ana --language ca --with-e2e > "$work/b1.log" 2>&1 || echo "bootstrap failed: $(cat "$work/b1.log")"
  caller=.github/workflows/patufet.yml
  [ "$(grep -c 'human-reviewer: "ana"' "$caller")" = 2 ] && echo "ok   reviewer filled in (fix-review and e2e)" || echo "FAIL reviewer filled in"
  [ "$(grep -c 'language: ca$' "$caller")" = 4 ] && echo "ok   language filled in" || echo "FAIL language filled in"
  grep -q 'e2e.yml@v1$' "$caller" && echo "ok   e2e job installed" || echo "FAIL e2e job installed"
  [ -f .github/patufet/e2e-up.sh ] && echo "ok   e2e hooks copied" || echo "FAIL e2e hooks copied"
  grep -q 'label create pass' "$GH_STUB_LOG" && echo "FAIL existing label recreated" || echo "ok   existing label left untouched"
  [ "$(grep -c 'label create' "$GH_STUB_LOG")" = 7 ] && echo "ok   7 missing labels created" || echo "FAIL 7 missing labels created"
  # the owner edits the caller, then re-runs the bootstrap with other options
  sed -i 's|echo "TODO: put your test/build commands here"|make test|' "$caller"
  before=$(cat .github/workflows/*.yml .github/patufet/* | md5sum)
  "$s/bootstrap.sh" --reviewer bob --language en --ref v9 > "$work/b2.log" 2>&1 || echo "bootstrap failed: $(cat "$work/b2.log")"
  [ "$(cat .github/workflows/*.yml .github/patufet/* | md5sum)" = "$before" ] \
    && echo "ok   re-run modifies no existing file (e2e job, test-command, ref kept)" \
    || echo "FAIL re-run modifies no existing file"
) > "$work/bootstrap.out"
cat "$work/bootstrap.out"
failures=$((failures + $(grep -c '^FAIL' "$work/bootstrap.out")))

echo "# prompts ↔ workflows ↔ docs"
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
