#!/usr/bin/env bash
# How much of the diff the reviewer read: the parts of diff-section.sh (not marked
# skip) that a Read call of the Claude run opened, or a Bash command (cat, sed...)
# named, by path or by file name. A Bash read counts only when the parts it names fit
# together in the output Claude Code shows whole (PATUFET_BASH_OUTPUT_BYTES, 30000 by
# default): a longer output is cut. A call whose result is an error or a permission
# denial reads nothing. With a PR number and some parts left unread, it also says so
# on the PR. It never changes the verdict: the person who merges decides.
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

bash_limit="${PATUFET_BASH_OUTPUT_BYTES:-30000}"

# The calls that succeeded: {name, path} for Read, {name, command} for Bash. jq fails
# on an unreadable file, which then counts as no reads
calls=$(jq -c '
  ([.[]? | select(.type == "user") | .message.content[]? | select(.type == "tool_result" and .is_error == true) | .tool_use_id]
   + [.[]? | select(.type == "result") | .permission_denials[]? | .tool_use_id]) as $failed
  | [.[]? | select(.type == "assistant") | .message.content[]?
     | select(.type == "tool_use" and (.id as $id | any($failed[]; . == $id) | not))
     | if .name == "Read" then {name, path: (.input.file_path // empty)}
       elif .name == "Bash" then {name, command: (.input.command // empty)}
       else empty end]' "$exec_file" 2>/dev/null) || calls='[]'

result=$(jq -c --argjson calls "$calls" --argjson limit "$bash_limit" '
  map(select(.skip | not)) as $parts
  # The parts a Bash command names, if they fit together in its output
  | ([$calls[] | select(.name == "Bash") | .command as $c
      | [$parts[] | select(.path as $p | ($c | contains($p)) or ($c | contains($p | split("/") | last)))]
      | select(map(.bytes) | add <= $limit) | .[].path]) as $bash
  | ([$calls[] | select(.name == "Read") | .path] + $bash) as $reads
  | $parts
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
