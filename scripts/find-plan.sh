#!/usr/bin/env bash
# Print the body of the approved implementation plan of an issue.
#
# Only comments written by an OWNER, MEMBER or COLLABORATOR of the repository
# are considered: on a public repository anyone can comment on an issue, and the
# implementer runs with write permissions, so the plan must never be taken from
# an untrusted author (prompt injection). The most recent matching comment wins.
#
# Usage: find-plan.sh <owner/repo> <issue-number> [<legacy-heading>]
#   The plan comment must contain the marker "<!-- patufet:plan -->".
#   <legacy-heading> (optional) additionally accepts comments whose body contains
#   that heading, for repositories migrating from a pre-template setup.
# Exit code 1 (and nothing on stdout) when no trusted plan exists.
set -euo pipefail

repo="${1:?usage: find-plan.sh <owner/repo> <issue-number> [<legacy-heading>]}"
issue="${2:?issue number is required}"
legacy="${3:-}"
marker="<!-- patufet:plan -->"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

plan=$(gh api "repos/$repo/issues/$issue/comments" --paginate \
  | jq -s -r -L "$here" --arg marker "$marker" --arg legacy "$legacy" \
      'include "trusted-comments"; add | latest_plan($marker; $legacy)')

if [ -z "$plan" ]; then
  echo "find-plan: issue #$issue has no plan comment ($marker) by a trusted author" >&2
  exit 1
fi
printf '%s\n' "$plan"
