#!/usr/bin/env bash
# Whether a stage runs the project's setup action (.github/patufet/setup/action.yml,
# a composite action with the setup steps of the project's CI: runtimes, tools,
# dependencies). Run from the checkout, before the agent changes anything.
#
# - No action in the checkout: no setup. A project that needs nothing beyond the
#   runner is a valid case.
# - With <restrict> "true" (fix-review on a PR whose author is not trusted, from
#   scripts/untrusted-pr-restriction.sh): no setup. The agent cannot run the PR's
#   code there anyway, and the action would be the PR's code run outside it.
#
# Usage: project-setup.sh <action-dir> [<restrict>]
# Prints "run=true|false" and "note=<why, for the job summary>" (GITHUB_OUTPUT format).
set -euo pipefail

dir="${1:?usage: project-setup.sh <action-dir> [<restrict>]}"
# Without <restrict> (implement, e2e) nothing is restricted; with it, anything but
# "false" is
restrict=false
[ $# -lt 2 ] || restrict="$2"

if [ ! -f "$dir/action.yml" ] && [ ! -f "$dir/action.yaml" ]; then
  echo "run=false"
  echo "note=none (no $dir/action.yml)"
elif [ "$restrict" != "false" ]; then
  echo "run=false"
  echo "note=skipped: the PR's author is not trusted, so the agent cannot run its code"
else
  echo "run=true"
  echo "note=$dir"
fi
