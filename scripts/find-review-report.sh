#!/usr/bin/env bash
# Print the latest automatic review report of a pull request, i.e. the most
# recent comment carrying the "<!-- patufet:review" marker written by a
# trusted author (the review bot or a repository collaborator). Untrusted
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
  | jq -s -r -L "$here" 'include "trusted-comments";
      add | [ .[] | trusted | select(.body | contains("<!-- patufet:review")) ] | last | .body // empty')

if [ -z "$report" ]; then
  echo "find-review-report: PR #$pr has no trusted review report" >&2
  exit 1
fi
printf '%s\n' "$report"
