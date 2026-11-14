#!/usr/bin/env bash
# Create the labels that do not exist yet. Existing labels are never modified:
# they may carry a colour or description the repository chose. Exits non-zero
# when a label is still missing afterwards: the agent could not apply it.
#
# Label names are compared like GitHub does, without case: `Blocked` is `blocked`.
#
# Usage: ensure-labels.sh <name>=<hex-color> ...
set -euo pipefail

list() { gh label list --limit 1000 --json name --jq '.[].name'; }
existing=$(list)
missing=0
for spec in "$@"; do
  name="${spec%=*}" color="${spec##*=}"
  grep -qixF "$name" <<< "$existing" && continue
  if gh label create "$name" --color "$color"; then
    echo "Created label '$name'"
  elif list | grep -qixF "$name"; then
    echo "Label '$name' was created concurrently"
  else
    echo "::error::Could not create label '$name'"
    missing=1
  fi
done
exit "$missing"
