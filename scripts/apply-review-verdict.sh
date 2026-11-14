#!/usr/bin/env bash
# Set the state after a review: read the verdict of the Claude run, route it
# (route-review.sh) and apply the result. The verdict label is set here with
# GITHUB_TOKEN, never by Claude, so it starts nothing: the caller's fix-review /
# e2e jobs read `next-stage` with `needs:` (decision 11).
#
# Usage: apply-review-verdict.sh <owner/repo> <pr-number> <cycle>
#   Environment:
#     STRUCTURED             structured output of the Claude action (JSON, may be empty)
#     CLAUDE_EXECUTION_FILE  execution file of the action; empty when it did not run
#     CI_STATE               state from wait-for-ci.sh (empty when CI was not waited for)
#     HEAD_SHA               the commit that was reviewed
#     LABEL_PASS, LABEL_WARNING, LABEL_FAIL, LABEL_NHR   label names
#     REVIEWER               login to mention when a person is needed (may be empty)
#     RUN_URL                link to this run, for the comments
#   Appends verdict=, next-stage=, needs-human= and reason= to $GITHUB_OUTPUT.
# Exit code 1 when the review produced no verdict.
set -euo pipefail

repo="${1:?usage: apply-review-verdict.sh <owner/repo> <pr-number> <cycle>}"
pr="${2:?pr number is required}"
cycle="${3:?cycle is required}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}" "${HEAD_SHA:?HEAD_SHA is not set}"
: "${LABEL_PASS:?}" "${LABEL_WARNING:?}" "${LABEL_FAIL:?}" "${LABEL_NHR:?}"

# No execution file = the action skipped itself before running Claude (e.g. its
# workflow-file validation on a PR that edits the caller) or the step timed out.
# Nothing to label; just fail visibly.
if [ -z "${CLAUDE_EXECUTION_FILE:-}" ]; then
  echo "::error::The Claude action did not finish (see its step log: workflow validation, missing token, timeout...). No verdict."
  exit 1
fi

verdict=$("$here/read-verdict.sh" review "$repo" "$pr" "cycle=$cycle")
needs_human=$(jq -rn --arg s "${STRUCTURED:-}" '$s | try (fromjson | .needs_human == true) catch false')
head=$("$here/pr-head.sh" "$pr")
moved=false
[ "$head" = "$HEAD_SHA" ] || moved=true

route=$("$here/route-review.sh" "$verdict" "${CI_STATE:-}" "$needs_human" "$moved")
echo "$route" >> "$GITHUB_OUTPUT"
field() { sed -n "s/^$1=//p" <<< "$route"; }
set_label() { "$here/set-verdict-label.sh" "$pr" "$1" "$LABEL_PASS" "$LABEL_WARNING" "$LABEL_FAIL" "$LABEL_NHR" "$2"; }
mention=""
[ -n "${REVIEWER:-}" ] && mention=" @$REVIEWER"

case "$(field reason)" in
  moved)
    echo "The PR has moved on from ${HEAD_SHA:0:7} to ${head:0:7}; the review of the new commit sets the state." ;;
  no-verdict)
    gh pr edit "$pr" --add-label "$LABEL_NHR"
    gh pr comment "$pr" --body "⚠️ patufet: review cycle $cycle produced no verdict. Manual review needed. See ${RUN_URL:-the run log}"
    exit 1 ;;
  forced-fail)
    echo "::warning::The reviewer returned 'pass' on a failed CI; the verdict is forced to 'fail'"
    set_label fail true
    gh pr comment "$pr" --body "⚠️ patufet: the reviewer returned \`pass\` although CI failed, so the workflow set \`$LABEL_FAIL\`. The report asks for no change, so no fix starts on its own: fix the cause, or remove and re-add \`$LABEL_FAIL\` to let fix-review try.$mention" ;;
  *)
    set_label "$(field verdict)" "$(field needs-human)" ;;
esac
