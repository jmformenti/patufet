#!/usr/bin/env bash
# Set the state after a live e2e test: read the verdict of the Claude run and
# apply it. A `fail` is labelled with GITHUB_TOKEN (it starts nothing) and
# returns `next-stage=fix-review`, which the caller's fix-e2e job reads with
# `needs:` (decision 11). A `pass` posts the final comment (e2e-pass-comment.sh).
#
# Usage: apply-e2e-verdict.sh <owner/repo> <pr-number> <run-key>
#   <run-key>: "<run_id>.<run_attempt>", which identifies this run's report.
#   Environment:
#     STRUCTURED             structured output of the Claude action (JSON, may be empty)
#     CLAUDE_OUTCOME         outcome of the Claude step (success, failure...)
#     CLAUDE_EXECUTION_FILE  execution file of the action; empty when it did not run
#     TESTED_SHA             the commit that was tested
#     LABEL_PASS, LABEL_WARNING, LABEL_FAIL   label names
#     REVIEWER               login to mention when everything works (may be empty)
#     RUN_URL                link to this run, for the comments
#   Appends verdict= and, on a failure, next-stage=fix-review to $GITHUB_OUTPUT.
# Exit code 1 when the test produced no verdict.
set -euo pipefail

repo="${1:?usage: apply-e2e-verdict.sh <owner/repo> <pr-number> <run-key>}"
pr="${2:?pr number is required}"
run_key="${3:?run key is required}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}" "${TESTED_SHA:?TESTED_SHA is not set}"
: "${LABEL_PASS:?}" "${LABEL_WARNING:?}" "${LABEL_FAIL:?}"

if [ -z "${CLAUDE_EXECUTION_FILE:-}" ]; then
  echo "::error::The Claude action did not run (see its step log). No verdict."
  exit 1
fi

verdict=$("$here/read-verdict.sh" e2e "$repo" "$pr" "run=$run_key")
echo "verdict=$verdict" >> "$GITHUB_OUTPUT"
if [ -z "$verdict" ] || [ "${CLAUDE_OUTCOME:-}" != "success" ]; then
  gh pr comment "$pr" --body "⚠️ patufet: the live e2e run produced no verdict (outcome: ${CLAUDE_OUTCOME:-unknown}). Manual check needed. See ${RUN_URL:-the run log}"
  exit 1
fi

if [ "$verdict" = "pass" ]; then
  body=$("$here/e2e-pass-comment.sh" "$pr" "$TESTED_SHA" "$LABEL_PASS" "${REVIEWER:-}")
  gh pr comment "$pr" --body "$body"
  exit 0
fi

head=$("$here/pr-head.sh" "$pr")
if [ "$head" != "$TESTED_SHA" ]; then
  echo "The PR has moved on from ${TESTED_SHA:0:7} to ${head:0:7}; the review of the new commit sets the state."
  exit 0
fi
"$here/set-verdict-label.sh" "$pr" fail "$LABEL_PASS" "$LABEL_WARNING" "$LABEL_FAIL"
echo "next-stage=fix-review" >> "$GITHUB_OUTPUT"
