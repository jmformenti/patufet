#!/usr/bin/env bash
# Replace the verdict label of a pull request. The three verdict labels are
# mutually exclusive.
#
# The labels are the state that people read; they do not start any stage. The
# workflows call this with GITHUB_TOKEN, whose events start nothing, and the
# caller chains the stages with `needs:` (decision 11). So one call is enough.
#
# Usage: set-verdict-label.sh <pr-number> <pass|warning|fail> <label-pass> <label-warning> <label-fail> [<label-needs-human-review> [<add true|false>]]
#   With the needs-human-review label: a pass removes it; add=true adds it.
set -euo pipefail

pr="${1:?pr number}"
verdict="${2:?verdict}"
label_pass="${3:?label pass}"
label_warning="${4:?label warning}"
label_fail="${5:?label fail}"
label_nhr="${6:-}"
add_nhr="${7:-false}"

case "$verdict" in
  pass)    add="$label_pass";    others=("$label_warning" "$label_fail") ;;
  warning) add="$label_warning"; others=("$label_pass" "$label_fail") ;;
  fail)    add="$label_fail";    others=("$label_pass" "$label_warning") ;;
  *) echo "set-verdict-label: unknown verdict '$verdict'" >&2; exit 1 ;;
esac

args=(--add-label "$add" --remove-label "${others[0]}" --remove-label "${others[1]}")
if [ -n "$label_nhr" ]; then
  if [ "$add_nhr" = true ]; then args+=(--add-label "$label_nhr")
  elif [ "$verdict" = pass ]; then args+=(--remove-label "$label_nhr")
  fi
fi
gh pr edit "$pr" "${args[@]}"
echo "PR #$pr labelled '$add'$([ "$add_nhr" = true ] && echo " and '$label_nhr'")"
