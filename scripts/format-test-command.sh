#!/usr/bin/env bash
# Print the "tests" part of the implement / fix-review prompt: the configured
# test command as a bash block, or an instruction to infer it.
#
# Usage: format-test-command.sh "<test-command, possibly multi-line or empty>"
# shellcheck disable=SC2016  # literal backticks (Markdown), nothing to expand
set -euo pipefail

if [ -n "${1:-}" ]; then
  printf '```bash\n%s\n```' "$1"
else
  printf '(No test command configured: reproduce locally the steps of the CI workflows in `.github/workflows/` that run on pull requests; if there are none, run what AGENTS.md, CLAUDE.md or README document as the tests and build. If a step cannot run on this runner (a missing tool or service), say so in the PR: CI checks the PR again. If no workflow runs on pull requests, nothing else will check it, so treat it as an open question.)'
fi
