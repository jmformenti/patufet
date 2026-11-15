#!/usr/bin/env bash
# How much of the diff the reviewer read: the parts of diff-section.sh (not marked
# skip) that a Read call of the Claude run opened. With a PR number and some parts
# left unread, it also says so on the PR. It never changes the verdict: the person
# who merges decides.
#
# A run without an execution file (the agent did not finish) reports nothing:
# apply-review-verdict.sh already says there is no verdict.
#
# Usage: diff-coverage.sh <index.json> <execution-file> [<pr> <cycle>]
# Prints "read=X" and "total=Y" on stdout (GITHUB_OUTPUT format).
set -euo pipefail

index="${1:?usage: diff-coverage.sh <index.json> <execution-file> [<pr> <cycle>]}"
exec_file="${2:-}"
pr="${3:-}"
cycle="${4:-}"

if [ ! -s "$index" ] || [ -z "$exec_file" ] || [ ! -f "$exec_file" ]; then
  exit 0
fi

# Paths given to Read; jq fails on an unreadable file, which then counts as no reads
reads=$(jq -c '[.[]? | select(.type == "assistant") | .message.content[]?
                | select(.type == "tool_use" and .name == "Read") | .input.file_path // empty]' \
          "$exec_file" 2>/dev/null) || reads='[]'

result=$(jq -c --argjson reads "$reads" '
  map(select(.skip | not))
  | map(. as $p | .read = any($reads[]; . == $p.path))
  | {read: map(select(.read)) | length, total: length,
     missing: map(select(.read | not) | .file) | unique}' "$index")

read=$(jq -r .read <<< "$result")
total=$(jq -r .total <<< "$result")
echo "read=$read"
echo "total=$total"

if [ -n "$pr" ] && [ "$read" -lt "$total" ]; then
  missing=$(jq -r '.missing | map("`" + gsub("[`\r\n]"; "_") + "`") | if length > 20 then (.[:20] | join(", ")) + ", …" else join(", ") end' <<< "$result")
  gh pr comment "$pr" --body "ℹ️ patufet: review cycle $cycle read $read of $total parts of the diff. Not read: $missing. The verdict does not take them into account: check those files by hand." \
    > /dev/null || echo "::warning::Could not comment the diff coverage on PR #$pr" >&2
fi
