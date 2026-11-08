#!/usr/bin/env bash
# Decide what follows a review, from facts only: the verdict the reviewer
# returned, the state of CI, whether the reviewer asked for a human, and whether
# the PR has moved on since the reviewed commit. No network, no labels: the
# workflow applies the result (decision 11).
#
# Usage: route-review.sh <verdict|""> <ci-state|""> <needs-human true|false> <head-moved true|false>
#   stdout, for $GITHUB_OUTPUT:
#     verdict=<pass|warning|fail|>     verdict label to set (empty: set none)
#     next-stage=<fix-review|e2e|>     stage the caller starts with `needs:` (empty: none)
#     needs-human=<true|false>         also add the needs-human-review label
#     reason=<ok|moved|no-verdict|forced-fail|human>
set -euo pipefail

verdict="${1:-}" ci_state="${2:-}" needs_human="${3:-false}" moved="${4:-false}"

out() { printf 'verdict=%s\nnext-stage=%s\nneeds-human=%s\nreason=%s\n' "$1" "$2" "$3" "$4"; }

case "$verdict" in
  ''|pass|warning|fail) ;;
  *) echo "route-review: unknown verdict '$verdict'" >&2; exit 1 ;;
esac

# A newer commit has its own review coming: this one must not set the state
if [ "$moved" = true ]; then out "" "" false moved; exit 0; fi
if [ -z "$verdict" ]; then out "" "" true no-verdict; exit 0; fi
# A red CI is never a pass. The report says pass, so fix-review would have
# nothing to apply: a person decides
if [ "$ci_state" = failure ] && [ "$verdict" = pass ]; then out fail "" true forced-fail; exit 0; fi
# The reviewer found a failure unrelated to the diff (decision 10): no code change
if [ "$needs_human" = true ]; then out "$verdict" "" true human; exit 0; fi

case "$verdict" in
  pass) out pass e2e false ok ;;
  *)    out "$verdict" fix-review false ok ;;
esac
