#!/usr/bin/env bash
# Fetch a consumer file (a stage's extra instructions) as it is on the PR's base commit,
# not from the checkout: the checkout is the PR, and a PR must not rewrite the
# instructions of the agents that review and fix it. A change to the file takes effect
# once it is merged, like a change to the caller workflow.
#
# A file missing on the base, or an empty path, gives no file: the stage runs without
# extra instructions. Any other failure does the same, with a warning.
#
# Usage: base-file.sh <owner/repo> <base-sha> <path> <out-file>
set -euo pipefail

repo="${1:?usage: base-file.sh <owner/repo> <base-sha> <path> <out-file>}"
ref="${2:?usage: base-file.sh <owner/repo> <base-sha> <path> <out-file>}"
path="${3:-}"
out="${4:?usage: base-file.sh <owner/repo> <base-sha> <path> <out-file>}"

rm -f "$out"
[ -n "$path" ] || exit 0

# Each segment URL-encoded, the slashes kept
enc=$(jq -rn --arg p "${path#./}" '$p | split("/") | map(@uri) | join("/")')
err=$(mktemp)
trap 'rm -f "$err" "$out.tmp"' EXIT
if gh api "repos/$repo/contents/$enc?ref=$ref" -H "Accept: application/vnd.github.raw+json" > "$out.tmp" 2> "$err"; then
  mv "$out.tmp" "$out"
elif ! grep -q 'HTTP 404' "$err"; then
  echo "::warning::Could not read $path on the base commit $ref; the stage runs without its extra instructions: $(head -c 300 "$err")" >&2
fi
