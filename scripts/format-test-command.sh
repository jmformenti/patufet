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
  printf '(No test command configured: run whatever the repository documents as its test suite and build, e.g. in CLAUDE.md or README.)'
fi
