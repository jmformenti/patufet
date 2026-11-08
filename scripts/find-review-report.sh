#!/usr/bin/env bash
# Print the latest automatic report of a pull request, i.e. the most recent
# comment carrying the "<!-- patufet:review" or "<!-- patufet:e2e" marker
# written by a trusted author (the bot or a repository collaborator). After a
# failed live test that is the e2e report, which is what fix-e2e must apply:
# the review before it said pass. Untrusted
# comments are ignored because the fix-review agent runs with write access and
# must never act on instructions planted by an arbitrary commenter.
#
# Usage: find-review-report.sh <owner/repo> <pr-number>
# Exit code 1 (and nothing on stdout) when there is no trusted report.
set -euo pipefail

repo="${1:?usage: find-review-report.sh <owner/repo> <pr-number>}"
pr="${2:?pr number is required}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

report=$(gh api "repos/$repo/issues/$pr/comments" --paginate \
  | jq -s -r -L "$here" 'include "trusted-comments"; add | reports("(review|e2e)") | last | .body // empty')

if [ -z "$report" ]; then
  echo "find-review-report: PR #$pr has no trusted review or e2e report" >&2
  exit 1
fi
printf '%s\n' "$report"
