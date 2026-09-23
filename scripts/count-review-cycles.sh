#!/usr/bin/env bash
# Print how many automatic review reports a pull request already has.
# A cycle is one trusted comment carrying the "<!-- patufet:review" marker
# (review.yml posts exactly one per run).
#
# Usage: count-review-cycles.sh <owner/repo> <pr-number>
set -euo pipefail

repo="${1:?usage: count-review-cycles.sh <owner/repo> <pr-number>}"
pr="${2:?pr number is required}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

gh api "repos/$repo/issues/$pr/comments" --paginate \
  | jq -s -r -L "$here" 'include "trusted-comments"; add | reports("review") | length'
