#!/usr/bin/env bash
# Wait for the CI of a commit and write its result as JSON. The CI is every
# workflow that GitHub started for the commit on a `pull_request` event, except
# the caller's own workflow: nothing to configure, and a workflow that its
# `paths:` / `branches:` filters leave out is not waited for (decision 12).
# A CI failure, a timeout or an unreadable API are results for the reviewer to
# report, not errors of this script: it exits 0 in all of them.
#
# Usage: wait-for-ci.sh <owner/repo> <sha> <own workflow path> <timeout-minutes> <result-file>
#   <own workflow path>: the caller's file, e.g. .github/workflows/patufet.yml
#   stdout: state=<success|failure|timeout|unavailable|none>, for $GITHUB_OUTPUT
#   PATUFET_CI_POLL_SECONDS: seconds between polls (default 30)
#
# Result: {state, sha, workflows: [{name, path, state}],
#          checks: [{name, state, conclusion, url, job_id}]}, where the checks are
# the jobs of those workflows (ci-section.sh reads the logs of the failed ones).
#
# A failed workflow does not end the wait: the report covers the whole CI, and at
# the deadline a failure still wins over the workflows that have not finished.
set -euo pipefail

repo="$1" sha="$2" own="$3" timeout_minutes="$4" result_file="$5"
poll="${PATUFET_CI_POLL_SECONDS:-30}"
max_errors=5

# shellcheck disable=SC2016  # jq programs, nothing to expand
state_of='if .status != "completed" then "pending"
  elif (.conclusion | IN("success", "neutral", "skipped")) then "success"
  else "failure" end'

# The latest run of each workflow started for this commit by a pull_request
# event. Several runs of one workflow (an earlier event, a re-run): the last wins.
fetch_runs() {
  gh api "repos/$repo/actions/runs?head_sha=$sha&event=pull_request&per_page=100" --paginate \
    | jq -s --arg own "$own" "[.[].workflow_runs[] | select(.event == \"pull_request\" and .path != \$own)]
        | group_by(.path) | map(max_by(.id))
        | map({id, name, path, conclusion, state: ($state_of)})"
}

# The jobs of one run, as checks. If they cannot be read, the run stands for them.
jobs_of() {  # jobs_of <run as JSON>
  local id
  id=$(jq -r .id <<<"$1")
  if gh api "repos/$repo/actions/runs/$id/jobs?per_page=100" --paginate > "$work/jobs" 2>/dev/null; then
    jq -s "[.[].jobs[] | {name, conclusion, state: ($state_of), url: .html_url, job_id: (.id | tostring)}]" "$work/jobs"
  else
    jq -c '[{name, conclusion, state, url: null, job_id: null}]' <<<"$1"
  fi
}

finish() {  # finish <state> [<runs file>]
  local runs="${2:-}" checks="[]"
  if [ -n "$runs" ]; then
    checks=$(jq -c '.[]' "$runs" | while IFS= read -r run; do jobs_of "$run"; done | jq -s 'add // []')
  else
    runs="$work/empty"; echo '[]' > "$runs"
  fi
  jq -n --arg state "$1" --arg sha "$sha" --slurpfile runs "$runs" --argjson checks "$checks" \
    '{state: $state, sha: $sha, workflows: ($runs[0] | map({name, path, state})), checks: $checks}' > "$result_file"
  echo "state=$1"
  exit 0
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
deadline=$(( $(date +%s) + timeout_minutes * 60 ))
errors=0 looked_again=false

while :; do
  if fetch_runs > "$work/runs" 2> "$work/err"; then
    errors=0
    total=$(jq length "$work/runs")
    pending=$(jq '[.[] | select(.state == "pending")] | length' "$work/runs")
    failed=$(jq '[.[] | select(.state == "failure")] | length' "$work/runs")
    if [ "$total" -eq 0 ]; then
      # The runs are created by the event that started this review; one more look
      # before saying that nothing runs CI on this commit
      if ! $looked_again; then looked_again=true; sleep "$poll"; continue; fi
      finish none
    fi
    if [ "$pending" -eq 0 ]; then
      if [ "$failed" -gt 0 ]; then finish failure "$work/runs"; else finish success "$work/runs"; fi
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      if [ "$failed" -gt 0 ]; then finish failure "$work/runs"; else finish timeout "$work/runs"; fi
    fi
  else
    errors=$((errors + 1))
    # A missing permission never heals: tell at once instead of idling until the deadline
    if grep -qE 'HTTP 40[134]' "$work/err" || [ "$errors" -ge "$max_errors" ] || [ "$(date +%s)" -ge "$deadline" ]; then
      echo "::warning::Could not read the workflow runs of $sha: $(head -1 "$work/err"). The caller's review job needs 'actions: read'." >&2
      finish unavailable
    fi
  fi
  sleep "$poll"
done
