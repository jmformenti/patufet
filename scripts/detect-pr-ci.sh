#!/usr/bin/env bash
# List the workflows that run on pull requests: the CI that the review waits
# for (wait-for-ci.sh discovers it at run time; the bootstrap only warns when
# there is none). Run from the root of a repository. A line-based reading of the
# `on:` section, enough for a warning.
#
# Output: one workflow file per line.
#
# patufet's own workflows and other Claude workflows are not CI: they are left out.
set -euo pipefail

for file in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$file" ] || continue
  case "$(basename "$file")" in patufet*) continue ;; esac
  grep -q 'anthropics/claude-code-action' "$file" && continue
  awk -v file="$file" '
    # pull_request, not pull_request_target nor pull_request_review
    function has_pr(s) { return s ~ /(^|[^a-z_])pull_request([^a-z_]|$)/ }
    /^[ \t]*(#|$)/ { next }
    {
      match($0, /^ */); ind = RLENGTH
      line = substr($0, ind + 1); sub(/[ \t]+#.*$/, "", line)
    }
    ind == 0 { on = (line ~ /^["\047]?on["\047]?:/); if (on && has_pr(line)) pr = 1; next }
    on && has_pr(line) { pr = 1 }
    END { if (pr) print file }
  ' "$file"
done
