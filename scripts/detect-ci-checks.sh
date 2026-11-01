#!/usr/bin/env bash
# List the CI jobs that run on pull requests, for the bootstrap to fill in
# `ci-checks`. Run from the root of a repository. A line-based reading of the
# YAML (the bootstrap only needs gh on the owner's machine), and the owner
# reviews its result.
#
# Output, tab-separated, one per job:
#   check    <check name>         the name GitHub gives the check
#   dynamic  <file>: <job id>     a matrix, an expression in `name:` or a reusable
#                                 workflow, whose name is only known at run time, or
#                                 a name with a comma outside parentheses, which the
#                                 comma-separated list of `ci-checks` would split
#
# patufet's own workflows and other Claude workflows are not CI: they are left out.
set -euo pipefail

for file in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$file" ] || continue
  case "$(basename "$file")" in patufet*) continue ;; esac
  grep -q 'anthropics/claude-code-action' "$file" && continue
  awk -v file="$file" '
    function has_pr(s) { return s ~ /(^|[^a-z_])pull_request([^a-z_]|$)/ }
    # A quoted value ends at its closing quote, whatever follows; only an unquoted
    # one can have a comment
    function name_value(s,   q, rest, i) {
      sub(/^name:[ \t]*/, "", s)
      q = substr(s, 1, 1)
      if (q == "\"" || q == "\047") {
        rest = substr(s, 2); i = index(rest, q)
        return i ? substr(rest, 1, i - 1) : rest
      }
      sub(/[ \t]+#.*$/, "", s); sub(/[ \t]+$/, "", s)
      return s
    }
    function close_job(   bare) {
      if (job != "") {
        bare = name; gsub(/\([^)]*\)/, "", bare)
        if (uses || matrix || name ~ /\$\{\{/ || bare ~ /,/) out = out "dynamic\t" file ": " job "\n"
        else out = out "check\t" (name != "" ? name : job) "\n"
      }
      job = ""; name = ""; uses = 0; matrix = 0; child = 0
    }
    /^[ \t]*(#|$)/ { next }
    {
      match($0, /^ */); ind = RLENGTH
      raw = substr($0, ind + 1); line = raw; sub(/[ \t]+#.*$/, "", line); sub(/[ \t]+$/, "", line)
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
      if (ind == child && line ~ /^name:/) name = name_value(raw)
      if (ind == child && line ~ /^uses:/) uses = 1
      if (line ~ /^matrix:/) matrix = 1
    }
    END { close_job(); if (pr) printf "%s", out }
  ' "$file"
done | awk '!seen[$0]++'
