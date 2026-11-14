#!/usr/bin/env bash
# Print the head commit of a pull request as it is now. A stage compares it with
# the commit its run started from: when they differ the PR has moved on, and the
# review of the new commit decides.
#
# Usage: pr-head.sh <pr-number>
set -euo pipefail

pr="${1:?usage: pr-head.sh <pr-number>}"
gh pr view "$pr" --json headRefOid | jq -r .headRefOid
