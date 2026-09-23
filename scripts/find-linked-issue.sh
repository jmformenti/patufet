#!/usr/bin/env bash
# Print the issue number a pull request implements, or nothing.
# Looks for a closing keyword in the PR body ("Closes #N", "fixes: #N",
# "Resolves owner/repo#N" for this same repository), then for the branch name
# "<branch-prefix>N".
#
# Usage: find-linked-issue.sh <owner/repo> <pr-number> <branch-prefix>
set -euo pipefail

repo="${1:?usage: find-linked-issue.sh <owner/repo> <pr-number> <branch-prefix>}"
pr="${2:?pr number is required}"
prefix="${3:?branch prefix is required}"

json=$(gh pr view "$pr" --repo "$repo" --json body,headRefName)
body=$(jq -r '.body // ""' <<< "$json")
branch=$(jq -r '.headRefName // ""' <<< "$json")

issue=""
while IFS= read -r ref; do
  ref="${ref##*[[:space:]]}"                       # owner/repo#N or #N
  target="${ref%#*}"
  if [ -z "$target" ] || [ "${target,,}" = "${repo,,}" ]; then
    issue="${ref##*#}"
    break
  fi
done < <(grep -oiE '\b(close[sd]?|fix(e[sd])?|resolve[sd]?):?[[:space:]]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+' <<< "$body" || true)

if [ -z "$issue" ] && [[ "$branch" == "$prefix"* ]]; then
  issue=$(grep -oE '^[0-9]+' <<< "${branch#"$prefix"}" || true)
fi

printf '%s' "$issue"
