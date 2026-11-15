#!/usr/bin/env bash
# The {{diff_section}} of the review prompt. Fetches the PR's diff, cuts it into parts
# with split-diff.sh and lists them, so the reviewer reads every part instead of the
# preview Claude Code shows of a large `gh pr diff`. diff-coverage.sh later counts the
# parts it read.
#
# When the diff cannot be fetched, the section falls back to `gh pr diff` and the index
# is empty (no coverage is reported).
#
# Usage: diff-section.sh <owner/repo> <pr> <out-dir>
# Writes <out-dir>/full.diff, <out-dir>/parts/ and <out-dir>/index.json; prints the
# section on stdout.
set -euo pipefail

repo="${1:?usage: diff-section.sh <owner/repo> <pr> <out-dir>}"
pr="${2:?pr number is required}"
out="${3:?output directory is required}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$out"
if ! gh pr diff "$pr" -R "$repo" > "$out/full.diff" 2>/dev/null \
  || ! "$here/split-diff.sh" "$out/full.diff" "$out"; then
  echo "::warning::Could not fetch or cut the diff of PR #$pr; the reviewer reads it with gh pr diff and no coverage is reported" >&2
  echo '[]' > "$out/index.json"
  echo "Read the diff with \`gh pr diff $pr\`. When Claude Code saves its output to a file because it is large, read that whole file, not only the preview."
  exit 0
fi

jq -r --argjson size "$(wc -c < "$out/full.diff")" '
  # File names come from the PR: keep them on one line and out of the table syntax
  def clean: gsub("[`|\r\n]"; "_");
  def count($n; $word): "\($n) \($word)\(if $n == 1 then "" else "s" end)";
  def part_name: "\(.file | clean)\(if .parts > 1 then " (\(.part)/\(.parts))" else "" end)";
  (map(select(.skip | not))) as $read
  | (map(select(.skip))) as $skip
  | if length == 0 then "The diff of this PR is empty."
    else
      "The diff of this PR is \(($size / 1024 * 10 | round) / 10) KB in \(count([.[].file] | unique | length; "file")), cut into \(count(length; "part")). Each part is a file you can read whole with one `Read` call.",
      "",
      "**Read every part in the table below, in order, with `Read`, before you write any comment.** Do not rely on `gh pr diff`: Claude Code shows only a preview of a large output. A step after you counts the parts you read and reports any you missed on the PR.",
      "",
      "| Part | File | Lines |",
      "|---|---|---|",
      ($read[] | "| `\(.path)` | \(part_name) | +\(.added) −\(.removed) |"),
      (if ($skip | length) > 0 then
        "",
        "Not expected to be read (lockfiles, minified or generated files, binaries); open them only if something points there:",
        "",
        ($skip[] | "- `\(.path)`: \(part_name)")
       else empty end),
      "",
      "A part marked (2/3) continues the previous part of the same file. For inline comments use the line numbers of the new file, from the `@@ -a,b +c,d @@` headers. The checkout is the PR merged into its base, so you can open a whole file with `Read` for context."
    end' "$out/index.json"
