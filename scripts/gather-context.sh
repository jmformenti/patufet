#!/usr/bin/env bash
# Gather what the review and e2e prompts need about the issue a pull request
# implements: the linked issue, its approved plan (trusted authors only) and
# the prompt section presenting it.
#
# Usage: gather-context.sh <owner/repo> <pr> <branch-prefix> <legacy-heading> <review|e2e> <out-dir>
# Writes <out-dir>/plan.md (empty without a plan) and <out-dir>/plan_section.md;
# prints "issue=N" and "has_plan=true|false" on stdout (GITHUB_OUTPUT format).
set -euo pipefail

repo="${1:?usage: gather-context.sh <owner/repo> <pr> <branch-prefix> <legacy-heading> <review|e2e> <out-dir>}"
pr="${2:?pr number is required}"
prefix="${3:?branch prefix is required}"
legacy="${4:-}"
mode="${5:?mode is required}"
out="${6:?output directory is required}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

issue=$("$here/find-linked-issue.sh" "$repo" "$pr" "$prefix")
has_plan=false
if [ -n "$issue" ] && "$here/find-plan.sh" "$repo" "$issue" "$legacy" > "$out/plan.md"; then
  has_plan=true
else
  : > "$out/plan.md"
fi
"$here/plan-section.sh" "$mode" "$issue" "$out/plan.md" > "$out/plan_section.md"

echo "issue=$issue"
echo "has_plan=$has_plan"
