#!/usr/bin/env bash
# Print the "plan" section of the review or e2e prompt: the approved plan when
# there is one, otherwise what to base the work on.
#
# Usage: plan-section.sh <review|e2e> <issue-number-or-empty> <plan-file>
#   <plan-file> is empty when the issue has no trusted plan.
# shellcheck disable=SC2016  # literal backticks (Markdown), nothing to expand
set -euo pipefail

mode="${1:?usage: plan-section.sh <review|e2e> <issue-or-empty> <plan-file>}"
issue="${2:-}"
plan_file="${3:?plan file is required}"

if [ -n "$issue" ] && [ -s "$plan_file" ]; then
  case "$mode" in
    review) intro="The PR implements issue #$issue, whose approved plan is reproduced below. Validate that the implementation follows it: promised files/changes, agreed decisions and the planned verification. Report every deviation (something missing, something done differently, out-of-scope additions) and say whether it is justified." ;;
    e2e)    intro="The PR implements issue #$issue. Its approved plan, reproduced below, tells you which functionality to exercise:" ;;
    *) echo "plan-section: unknown mode '$mode'" >&2; exit 2 ;;
  esac
  printf '%s\n\n<plan>\n%s\n</plan>' "$intro" "$(cat "$plan_file")"
elif [ -n "$issue" ]; then
  case "$mode" in
    review) printf 'The PR references issue #%s but that issue has no approved plan; review the PR on its own merits against the issue description (`gh issue view %s`).' "$issue" "$issue" ;;
    e2e)    printf 'The PR references issue #%s (`gh issue view %s`); use it to know which functionality to exercise.' "$issue" "$issue" ;;
  esac
else
  case "$mode" in
    review) printf 'The PR is not linked to any issue; review it on its own merits.' ;;
    e2e)    printf 'The PR is not linked to any issue; derive what to test from the diff and the PR description.' ;;
  esac
fi
