#!/usr/bin/env bash
# List the CI jobs that run on pull requests, for the bootstrap to fill in
# `ci-checks`. Run from the root of a repository. A line-based reading of the
# YAML (the bootstrap only needs gh on the owner's machine), and the owner
# reviews its result.
#
# Output, tab-separated, one per job:
#   check    <check name>         the name GitHub gives the check
#   dynamic  <file>: <job id>     a job that must be listed by hand: a matrix, an
#                                 expression in `name:` or a reusable workflow (the
#                                 name is only known at run time), a `name:` beyond
#                                 this simple reading of YAML (escapes, block scalars,
#                                 aliases...), or a name that the comma-separated list
#                                 of `ci-checks` would not keep whole
#
# A wrong name makes every review wait until the timeout and miss that check's
# result, so only the names read with certainty are emitted.
#
# patufet's own workflows and other Claude workflows are not CI: they are left out.
set -euo pipefail

for file in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$file" ] || continue
  case "$(basename "$file")" in patufet*) continue ;; esac
  grep -q 'anthropics/claude-code-action' "$file" && continue
  awk -v file="$file" '
    function has_pr(s) { return s ~ /(^|[^a-z_])pull_request([^a-z_]|$)/ }
    # The value of a `name:` line; sets unreadable when it is not a plain one-line
    # string. A quoted value ends at its closing quote and may only be followed by a
    # comment, which rules out the doubled quote of a single-quoted string.
    function name_value(s,   q, rest, i) {
      sub(/^name:[ \t]*/, "", s)
      q = substr(s, 1, 1)
      if (q == "\"" || q == "\047") {
        rest = substr(s, 2); i = index(rest, q)
        if (!i || substr(rest, i + 1) !~ /^[ \t]*(#.*)?$/) unreadable = 1
        s = substr(rest, 1, i - 1)
        if (q == "\"" && s ~ /\\/) unreadable = 1
        return s
      }
      sub(/^#.*$/, "", s); sub(/[ \t]+#.*$/, "", s); sub(/[ \t]+$/, "", s)
      if (s == "" || s ~ /^[>|&*!%@`{[]/) unreadable = 1
      return s
    }
    # The same rules as the list of wait-for-ci.sh: no comma outside parentheses,
    # balanced parentheses, no space at the ends
    function fits_the_list(s,   i, c, depth) {
      if (s ~ /^[ \t]|[ \t]$/) return 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "(") depth++
        else if (c == ")") { if (!depth) return 0; depth-- }
        else if (c == "," && !depth) return 0
      }
      return !depth
    }
    function close_job() {
      if (job != "") {
        if (uses || matrix || unreadable || name ~ /\$\{\{/ || !fits_the_list(name)) out = out "dynamic\t" file ": " job "\n"
        else out = out "check\t" (name != "" ? name : job) "\n"
      }
      job = ""; name = ""; uses = 0; matrix = 0; child = 0; unreadable = 0; after_name = 0
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
      if (after_name && ind > child) unreadable = 1  # a value continued on the next line
      after_name = 0
      if (ind == child && line ~ /^name:/) { name = name_value(raw); after_name = 1 }
      if (ind == child && line ~ /^uses:/) uses = 1
      if (line ~ /^matrix:/) matrix = 1
    }
    END { close_job(); if (pr) printf "%s", out }
  ' "$file"
done | awk '!seen[$0]++'
