#!/usr/bin/env bash
# Create the labels that do not exist yet. Existing labels are never modified:
# they may carry a colour or description the repository chose.
#
# Usage: ensure-labels.sh <name>=<hex-color> ...
set -euo pipefail

existing=$(gh label list --limit 1000 --json name --jq '.[].name')
for spec in "$@"; do
  name="${spec%=*}" color="${spec##*=}"
  grep -qxF "$name" <<< "$existing" && continue
  if gh label create "$name" --color "$color"; then
    echo "Created label '$name'"
  else
    echo "::warning::Could not create label '$name' (created concurrently?)"
  fi
done
