#!/usr/bin/env bash
# Print the comment for a PR whose live e2e test passed. It only says "ready for
# merge" if the PR is still at the tested commit and still labelled pass: the
# verdict can change while e2e runs (a new push, a person relabels).
#
# Usage: e2e-pass-comment.sh <pr> <tested-sha> <label-pass> [human-reviewer]
set -euo pipefail

pr="$1" tested="$2" label_pass="$3" reviewer="${4:-}"

state=$(gh pr view "$pr" --json headRefOid,labels)
head=$(jq -r .headRefOid <<< "$state")

if [ "$head" != "$tested" ]; then
  echo "ℹ️ patufet: the live e2e test passed on ${tested:0:7}, but the PR has moved on to ${head:0:7}; the new commits go through review (and e2e) again."
elif ! jq -e --arg l "$label_pass" 'any(.labels[]; .name == $l)' <<< "$state" > /dev/null; then
  echo "ℹ️ patufet: the live e2e test passed on ${tested:0:7}, but the PR is no longer labelled \`$label_pass\`, so it is not ready for merge. See the latest review report."
else
  mention=""
  [ -n "$reviewer" ] && mention=" @$reviewer"
  echo "✅ patufet: code review and live e2e test passed. Ready for human review and merge.$mention"
fi
