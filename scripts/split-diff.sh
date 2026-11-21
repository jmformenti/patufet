#!/usr/bin/env bash
# Cut a unified diff (the output of `gh pr diff`) into parts the reviewer can read
# whole with one Read call. A large diff given to the agent in one piece is saved by
# Claude Code to a file and shown as a short preview, and the agent often reviews the
# preview only.
#
# Each file of the diff becomes one or more parts of at most MAX_LINES lines and
# MAX_BYTES bytes. A file is cut between hunks, and a hunk that is too large on its own
# is cut between lines. The parts, concatenated in order, are exactly the input.
# Lockfiles, minified or generated files and binary files are marked "skip": they are
# listed, but nobody expects them to be read.
#
# The diff is the PR's content: it is only read and copied, never executed.
#
# Usage: split-diff.sh <diff-file> <out-dir>
# Writes <out-dir>/parts/NNN-<name>[.K].diff and <out-dir>/index.json, a list of
# {path, file, part, parts, lines, bytes, added, removed, skip, continues}; continues is
# {old, new}, the line numbers of the first line of a part that starts inside a hunk.
set -euo pipefail

diff_file="${1:?usage: split-diff.sh <diff-file> <out-dir>}"
out="${2:?usage: split-diff.sh <diff-file> <out-dir>}"

python3 - "$diff_file" "$out" <<'PY'
import json
import os
import re
import sys

diff_path, out = sys.argv[1], sys.argv[2]
MAX_LINES = int(os.environ.get("PATUFET_DIFF_PART_LINES", "600"))
MAX_BYTES = int(os.environ.get("PATUFET_DIFF_PART_BYTES", "20000"))
SKIP = re.compile(
    r"(^|/)(package-lock\.json|npm-shrinkwrap\.json|yarn\.lock|pnpm-lock\.yaml|go\.sum|gradle\.lockfile|[^/]*\.lock)$"
    r"|\.min\.[A-Za-z0-9]+$|\.map$|\.snap$"
)

data = open(diff_path, "rb").read()
# Lines with their newline, so that joining them gives the input back byte for byte
lines = [l for l in re.split(rb"(?<=\n)", data) if l]

files = []  # each: list of lines, starting at "diff --git"
for line in lines:
    if line.startswith(b"diff --git ") or not files:
        files.append([])
    files[-1].append(line)


def unquote(name):
    # git quotes a path with special characters: "b/caf\303\251 x.txt"
    if len(name) >= 2 and name[0] == name[-1] == '"':
        raw = name[1:-1].encode("utf-8")
        raw = re.sub(rb"\\([0-7]{3})", lambda m: bytes([int(m.group(1), 8)]), raw)
        raw = re.sub(rb"\\(.)", lambda m: {b"n": b"\n", b"t": b"\t"}.get(m.group(1), m.group(1)), raw)
        name = raw.decode("utf-8", "replace")
    return name


def file_name(block):
    old = new = None
    for line in block:
        text = line.decode("utf-8", "replace").rstrip("\r\n")
        if text.startswith("@@"):
            break
        if text.startswith("--- ") and old is None:
            old = unquote(text[4:].split("\t")[0])
        elif text.startswith("+++ ") and new is None:
            new = unquote(text[4:].split("\t")[0])
        elif text.startswith("rename to "):
            new = "b/" + text[len("rename to "):]
        elif text.startswith("Binary files "):
            m = re.match(r"Binary files (.+) and (.+) differ$", text)
            if m:
                old, new = unquote(m.group(1)), unquote(m.group(2))
    for name in (new, old):
        if name and name != "/dev/null":
            return name[2:] if name[:2] in ("a/", "b/") else name
    head = block[0].decode("utf-8", "replace").rstrip("\r\n")
    if head.startswith("diff --git ") and " b/" in head:
        return head.rsplit(" b/", 1)[1].strip('"')
    return head[:80] or "unnamed"


def is_binary(block):
    return any(l.startswith(b"Binary files ") or l.startswith(b"GIT binary patch") for l in block)


def chunks(block):
    """Cut one file's lines into groups within the limits: between hunks when it can."""
    units, current = [], []
    for line in block:  # units: one per hunk, the first with the header
        if line.startswith(b"@@") and current:
            units.append(current)
            current = []
        current.append(line)
    if current:
        units.append(current)
    if len(units) > 1 and not units[0][0].startswith(b"@@"):
        units[1] = units[0] + units[1]  # the header travels with the first hunk
        del units[0]
    pieces = []
    for unit in units:  # a unit too large on its own is cut between lines
        piece = []
        for line in unit:
            if piece and (len(piece) >= MAX_LINES or sum(map(len, piece)) + len(line) > MAX_BYTES):
                pieces.append(piece)
                piece = []
            piece.append(line)
        if piece:
            pieces.append(piece)
    groups, group = [], []
    for piece in pieces:
        if group and (len(group) + len(piece) > MAX_LINES or sum(map(len, group)) + sum(map(len, piece)) > MAX_BYTES):
            groups.append(group)
            group = []
        group = group + piece
    if group:
        groups.append(group)
    return groups


HUNK = re.compile(rb"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def positions(block):
    """For each line of a file's diff, the old and new line numbers it stands at, or None
    outside a hunk. A part that starts inside a hunk has no @@ header of its own: these
    numbers tell the reviewer where it is, for its inline comments."""
    result, old, new, no_old, no_new = [], None, None, False, False
    for line in block:
        m = HUNK.match(line)
        if m:
            old, new = max(int(m.group(1)), 1), max(int(m.group(3)), 1)
            # "-0,0" is a new file and "+0,0" a deleted one: that side has no lines
            no_old, no_new = m.group(2) == b"0", m.group(4) == b"0"
            result.append(None)
            continue
        result.append((None if no_old else old, None if no_new else new) if old is not None else None)
        if old is None:
            continue
        if line.startswith(b"-"):
            old += 1
        elif line.startswith(b"+"):
            new += 1
        elif line.startswith(b" "):
            old, new = old + 1, new + 1
    return result


def safe(name):
    name = re.sub(r"[^A-Za-z0-9._-]+", "_", name).strip("._") or "file"
    return name[-60:]


parts_dir = os.path.join(out, "parts")
os.makedirs(parts_dir, exist_ok=True)
index = []
for n, block in enumerate(files, 1):
    name = file_name(block)
    skip = bool(SKIP.search(name)) or is_binary(block)
    groups = chunks(block)
    header = 0  # the lines before the first hunk: "--- a/x" is not a removed line
    while header < len(block) and not block[header].startswith(b"@@"):
        header += 1
    where = positions(block)
    start = 0
    for k, group in enumerate(groups, 1):
        at, start = where[start], start + len(group)
        suffix = f".{k}" if len(groups) > 1 else ""
        path = os.path.join(parts_dir, f"{n:03d}-{safe(name)}{suffix}.diff")
        with open(path, "wb") as fh:
            fh.write(b"".join(group))
        body = group[header:] if k == 1 else group
        index.append({
            "path": os.path.abspath(path),
            "file": name,
            "part": k,
            "parts": len(groups),
            "lines": len(group),
            "bytes": sum(map(len, group)),
            "added": sum(1 for l in body if l.startswith(b"+")),
            "removed": sum(1 for l in body if l.startswith(b"-")),
            "skip": skip,
            # set when the part starts inside a hunk: the old and new line of its first line
            # (null on the side a new or deleted file does not have)
            "continues": {"old": at[0], "new": at[1]} if at else None,
        })

with open(os.path.join(out, "index.json"), "w", encoding="utf-8") as fh:
    json.dump(index, fh, indent=1, ensure_ascii=False)
PY
