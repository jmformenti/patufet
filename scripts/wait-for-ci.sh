#!/usr/bin/env bash
# Wait for the CI checks of a commit and write their result as JSON. A CI
# failure, a timeout or an unreadable API are results for the reviewer to report,
# not errors of this script: it exits 0 in all of them.
#
# Usage: wait-for-ci.sh <owner/repo> <sha> "<check names>" <timeout-minutes> <result-file>
#   Names are separated by commas; a comma inside parentheses belongs to the name
#   ("test (ubuntu, 21)", a matrix job). With several lines, each line is one name
#   and commas mean nothing, for a name with any other comma.
#   stdout: state=<success|failure|timeout|unavailable>, for $GITHUB_OUTPUT
#   PATUFET_CI_POLL_SECONDS: seconds between polls (default 30)
#
# A failed check does not end the wait: the report covers every listed check, and
# at the deadline a failure still wins over the checks that have not finished.
set -euo pipefail

repo="$1" sha="$2" names="$3" timeout_minutes="$4" result_file="$5"
poll="${PATUFET_CI_POLL_SECONDS:-30}"
max_errors=5

# shellcheck disable=SC2016  # $s is a jq variable
wanted=$(jq -cn --arg s "$names" '
  [$s | sub("\\s+$"; "")
   | if contains("\n") then split("\n")[] else scan("(?:[^,(]|\\([^)]*\\))+") end
   | sub("^\\s+"; "") | sub("\\s+$"; "") | select(. != "")]')

# The check runs of the commit, slurped from the pages `gh api --paginate` prints
fetch_runs() {
  gh api "repos/$repo/commits/$sha/check-runs?per_page=100&filter=latest" --paginate | jq -s '[.[].check_runs[]]'
}

# One entry per wanted name. Two runs can share a name (the same job on `push`
# and on `pull_request`): the worst one represents them.
evaluate() {
  jq --argjson wanted "$wanted" --arg sha "$sha" '
    def state:
      if .status != "completed" then "pending"
      elif (.conclusion | IN("success", "neutral", "skipped")) then "success"
      else "failure" end;
    . as $runs
    | [$wanted[] as $name
       | [$runs[] | select(.name == $name) | . + {state: state}] as $mine
       | ([$mine[] | select(.state == "failure")] + [$mine[] | select(.state == "pending")] + $mine)[0] as $r
       | {name: $name,
          state: ($r.state // "missing"),
          conclusion: $r.conclusion,
          url: $r.details_url,
          job_id: (if $r.app.slug == "github-actions"
                   then (($r.details_url // "") | capture("/actions/runs/[0-9]+/job/(?<id>[0-9]+)").id)? // null
                   else null end)}] as $checks
    | {sha: $sha, checks: $checks, seen: ($runs | map(.name) | unique)}'
}

finish() {  # finish <state> <file with the evaluation>
  jq --arg state "$1" '{state: $state} + .' "$2" > "$result_file"
  echo "state=$1"
  exit 0
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
deadline=$(( $(date +%s) + timeout_minutes * 60 ))
errors=0

while :; do
  if fetch_runs > "$work/runs" 2> "$work/err"; then
    errors=0
    evaluate < "$work/runs" > "$work/eval"
    open=$(jq '[.checks[] | select(.state == "pending" or .state == "missing")] | length' "$work/eval")
    failed=$(jq '[.checks[] | select(.state == "failure")] | length' "$work/eval")
    if [ "$open" -eq 0 ]; then
      if [ "$failed" -gt 0 ]; then finish failure "$work/eval"; else finish success "$work/eval"; fi
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      missing=$(jq -r '[.checks[] | select(.state == "missing") | .name] | join(", ")' "$work/eval")
      if [ -n "$missing" ]; then
        echo "::warning::No check named: $missing. Checks seen on $sha: $(jq -r '.seen | join(", ")' "$work/eval")" >&2
      fi
      if [ "$failed" -gt 0 ]; then finish failure "$work/eval"; else finish timeout "$work/eval"; fi
    fi
  else
    errors=$((errors + 1))
    # A missing permission never heals: tell at once instead of idling until the deadline
    if grep -qE 'HTTP 40[134]' "$work/err" || [ "$errors" -ge "$max_errors" ] || [ "$(date +%s)" -ge "$deadline" ]; then
      echo "::warning::Could not read the checks of $sha: $(head -1 "$work/err"). The caller's review job needs 'checks: read' on a private repository." >&2
      jq -n --arg sha "$sha" --argjson wanted "$wanted" \
        '{sha: $sha, checks: [$wanted[] | {name: ., state: "unknown"}], seen: []}' > "$work/eval"
      finish unavailable "$work/eval"
    fi
  fi
  sleep "$poll"
done
