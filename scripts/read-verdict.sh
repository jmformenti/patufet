#!/usr/bin/env bash
# Print the verdict of the Claude run that just finished, or nothing.
#
# The structured output of the action ($STRUCTURED, JSON) is the source of
# truth. When it is missing (e.g. max-turns reached after posting), fall back
# to the marker of the report comment posted *by this run*: a trusted
# "<!-- patufet:<kind> ... <key> verdict=V -->". A report from an earlier run
# never counts, otherwise a run that failed silently would inherit the previous
# verdict and the flow would stall with no hand-over.
#
# Usage: read-verdict.sh <review|e2e> <owner/repo> <pr-number> <key>
#   <key>: "cycle=N" for a review, "run=<run_id>.<run_attempt>" for e2e.
set -euo pipefail

kind="${1:?usage: read-verdict.sh <review|e2e> <owner/repo> <pr-number> <key>}"
repo="${2:?repository is required}"
pr="${3:?pr number is required}"
key="${4:?key is required}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$kind" in
  review) allowed='^(pass|warning|fail)$' ;;
  e2e)    allowed='^(pass|fail)$' ;;
  *) echo "read-verdict: unknown kind '$kind'" >&2; exit 2 ;;
esac

verdict=$(jq -r '.verdict // empty' <<< "${STRUCTURED:-}" 2>/dev/null || true)
if [ -z "$verdict" ]; then
  echo "read-verdict: no structured output; looking for the $kind report with '$key'" >&2
  verdict=$(gh api "repos/$repo/issues/$pr/comments" --paginate \
    | jq -s -r -L "$here" --arg kind "$kind" --arg key "$key" \
        'include "trusted-comments"; add | verdict($kind; $key)')
fi

if [ -n "$verdict" ] && ! grep -qE "$allowed" <<< "$verdict"; then
  echo "read-verdict: ignoring invalid $kind verdict '$verdict'" >&2
  verdict=""
fi
printf '%s' "$verdict"
