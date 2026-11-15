#!/usr/bin/env bash
# Value of claude-code-action's restrict_untrusted_prs for fix-review. On a pull
# request whose author it cannot confirm has write access, the action denies the
# commands that run code from the checkout (test runners, package managers,
# interpreters, shells). It never trusts a bot, so every PR that implement opens
# (author claude[bot]) would get fixes the agent cannot test.
#
# patufet trusts the code of the same authors as its trust filter: claude[bot],
# whose PRs only implement opens from a plan a person approved, and people with
# write or admin access. Prints "false" (lift the restriction) for them and "true"
# (keep it) for anyone else, and also when the permission cannot be read.
#
# Usage: untrusted-pr-restriction.sh <owner/repo> <pr-author-login>
set -euo pipefail

repo="${1:?usage: untrusted-pr-restriction.sh <owner/repo> <pr-author-login>}"
author="${2:-}"

if [ "$author" = "claude[bot]" ]; then
  echo false
  exit 0
fi
# A user login: letters, digits and single hyphens. Anything else (another bot, an
# empty login) keeps the restriction without asking the API.
if ! [[ "$author" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]]; then
  echo true
  exit 0
fi
permission=$(gh api "repos/$repo/collaborators/$author/permission" 2>/dev/null | jq -r '.permission // empty' 2>/dev/null) || permission=""
case "$permission" in
  admin | write) echo false ;;
  *) echo true ;;
esac
