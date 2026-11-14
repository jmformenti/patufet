#!/usr/bin/env bash
# The two checks around the fix-review agent.
#
#   before: decide whether to fix at all. A push since the commit this run
#     started from has its own review coming, which decides again: fixing the old
#     report would push a stale change. At the cycle limit the PR goes to a person.
#   after: check that the agent pushed. A fix that ends without a push (an
#     ambiguous point it left as a question, nothing it may change, denied tools)
#     starts no new review, so the PR would stay at its verdict with nobody told:
#     it goes to a person too.
#
# Usage: fix-gate.sh <before|after> <pr-number>
#   Environment:
#     STARTED_SHA   the commit this run started from
#     COUNT         review cycles already done   (before)
#     MAX_CYCLES    limit of review cycles       (before)
#     LABEL_NHR     needs-human-review label
#     REVIEWER      login to mention (may be empty)
#     RUN_URL       link to this run, for the comment (after)
#   before appends state=<moved|limit|fix> to $GITHUB_OUTPUT.
set -euo pipefail

mode="${1:?usage: fix-gate.sh <before|after> <pr-number>}"
pr="${2:?pr number is required}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${STARTED_SHA:?STARTED_SHA is not set}" "${LABEL_NHR:?LABEL_NHR is not set}"

hand_over() {  # hand_over <comment>
  local mention=""
  [ -n "${REVIEWER:-}" ] && mention=" @$REVIEWER"
  "$here/ensure-labels.sh" "$LABEL_NHR=5319E7"
  gh pr edit "$pr" --add-label "$LABEL_NHR"
  gh pr comment "$pr" --body "$1$mention"
}

head=$("$here/pr-head.sh" "$pr")

case "$mode" in
  before)
    : "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}" "${COUNT:?COUNT is not set}" "${MAX_CYCLES:?MAX_CYCLES is not set}"
    if [ "$head" != "$STARTED_SHA" ]; then
      echo "The PR has moved on from ${STARTED_SHA:0:7} to ${head:0:7}; its new review decides again. Nothing to fix."
      echo "state=moved" >> "$GITHUB_OUTPUT"
    elif [ "$COUNT" -ge "$MAX_CYCLES" ]; then
      hand_over "⚠️ patufet: $MAX_CYCLES automatic review cycles reached without a \`pass\` verdict. Manual review needed."
      echo "state=limit" >> "$GITHUB_OUTPUT"
    else
      echo "state=fix" >> "$GITHUB_OUTPUT"
    fi
    ;;
  after)
    if [ "$head" != "$STARTED_SHA" ]; then
      echo "The PR moved from ${STARTED_SHA:0:7} to ${head:0:7}: the push starts a new review."
    else
      hand_over "⚠️ patufet: fix-review ended without pushing a change, so no new review starts. Its comments on this PR, if any, say why. Manual review needed. See ${RUN_URL:-the run log}"
    fi
    ;;
  *) echo "fix-gate: unknown mode '$mode'" >&2; exit 2 ;;
esac
