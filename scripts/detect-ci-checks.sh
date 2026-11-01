#!/usr/bin/env bash
# List the CI jobs that run on pull requests, for the bootstrap to fill in
# `ci-checks`. Run from the root of a repository. A line-based reading of the
# YAML (the bootstrap only needs gh on the owner's machine), and the owner
# reviews its result.
#
# Output, tab-separated, one per job:
#   check    <check name>         the name GitHub gives the check
#   dynamic  <file>: <job id>     a matrix, an expression in `name:` or a reusable
#                                 workflow: the name is only known at run time
#
# patufet's own workflows and other Claude workflows are not CI: they are left out.
set -euo pipefail

for file in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$file" ] || continue
  case "$(basename "$file")" in patufet*) continue ;; esac
  grep -q 'anthropics/claude-code-action' "$file" && continue
  awk -v file="$file" '
    function has_pr(s) { return s ~ /(^|[^a-z_])pull_request([^a-z_]|$)/ }
    function close_job() {
      if (job != "") {
        if (uses || matrix || name ~ /\$\{\{/) out = out "dynamic\t" file ": " job "\n"
        else out = out "check\t" (name != "" ? name : job) "\n"
      }
      job = ""; name = ""; uses = 0; matrix = 0; child = 0
    }
    /^[ \t]*(#|$)/ { next }
    {
      match($0, /^ */); ind = RLENGTH
      line = substr($0, ind + 1); sub(/[ \t]+#.*$/, "", line); sub(/[ \t]+$/, "", line)
    }
    ind == 0 {
      section = ""
      if (line ~ /^["\047]?on["\047]?:/) { section = "on"; if (has_pr(line)) pr = 1 }
      else if (line ~ /^jobs:/) section = "jobs"
      next
    }
    section == "on" { if (has_pr(line)) pr = 1; next }
    section == "jobs" {
      if (!job_ind) job_ind = ind
      if (ind == job_ind) { close_job(); job = line; sub(/:.*$/, "", job); gsub(/["\047]/, "", job); next }
      if (!child) child = ind
      if (ind == child && line ~ /^name:/) { name = line; sub(/^name:[ \t]*/, "", name); gsub(/^["\047]|["\047]$/, "", name) }
      if (ind == child && line ~ /^uses:/) uses = 1
      if (line ~ /^matrix:/) matrix = 1
    }
    END { close_job(); if (pr) printf "%s", out }
  ' "$file"
done | awk '!seen[$0]++'
