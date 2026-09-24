#!/usr/bin/env bash
# Append a short summary of a Claude run to the job summary: outcome, turns,
# duration and the cost reported by Claude Code, plus any extra "Key: value"
# lines (verdict, cycle...). With an OAuth token the cost is what the same run
# would cost on the API, not what the subscription is charged.
#
# Usage: run-summary.sh <stage> <execution-file-or-empty> ["Key: value" ...]
set -euo pipefail

stage="${1:?usage: run-summary.sh <stage> <execution-file> [\"Key: value\" ...]}"
file="${2:-}"
shift 2 || shift $#
out="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

{
  echo "### patufet / $stage"
  echo
  echo "| | |"
  echo "|---|---|"
  if [ -n "$file" ] && [ -f "$file" ]; then
    jq -r '
      [ .[]? | select(.type == "result") ] | last
      | if . == null then "| Claude run | no result message |"
        else
          "| Result | \(.subtype // "?")\(if .is_error then " (error)" else "" end) |",
          "| Turns | \(.num_turns // "?") |",
          "| Duration | \(if .duration_ms then "\((.duration_ms / 60000 * 10 | floor) / 10) min" else "?" end) |",
          "| Cost reported by Claude Code | \(if .total_cost_usd then "$\(.total_cost_usd * 100 | round / 100)" else "?" end) |"
        end' "$file" 2>/dev/null || echo "| Claude run | unreadable execution file |"
  else
    echo "| Claude run | did not run |"
  fi
  for line in "$@"; do
    echo "| ${line%%:*} | ${line#*: } |"
  done
} >> "$out"
