#!/usr/bin/env bash
# Install patufet in the repository of the current directory.
#
#   bash <(curl -sSL https://raw.githubusercontent.com/jmformenti/patufet/main/scripts/bootstrap.sh) \
#     --reviewer <github-login> [--language ca] [--ref v1] [--with-e2e] [--dry-run]
#
# What it does (idempotent, never overwrites an existing file):
#   1. copies the caller workflows, the prompt extension files, the e2e hooks
#      (only with --with-e2e) and the /plan-issue command;
#   2. fills in --reviewer / --language / --ref in the caller workflow;
#   3. creates the 8 flow labels;
#   4. checks that CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY is set.
set -euo pipefail

TEMPLATE_REPO="jmformenti/patufet"
reviewer=""
language="en"
ref="v1"
with_e2e=false
dry_run=false

usage() { sed -n '2,15p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --reviewer) reviewer="$2"; shift 2 ;;
    --language) language="$2"; shift 2 ;;
    --ref) ref="$2"; shift 2 ;;
    --with-e2e) with_e2e=true; shift ;;
    --dry-run) dry_run=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

command -v gh >/dev/null || { echo "gh (GitHub CLI) is required" >&2; exit 1; }
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "Run this from inside a git repository" >&2; exit 1; }
cd "$(git rev-parse --show-toplevel)"
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
echo "Installing patufet@$ref into $repo (reviewer: ${reviewer:-none}, language: $language, e2e: $with_e2e)"

run() { if $dry_run; then echo "[dry-run] $*"; else "$@"; fi; }

# --- locate the templates (local clone or download) -------------------------
script_dir=""
if cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null; then script_dir="$(pwd)"; cd - >/dev/null; fi
if [ -n "$script_dir" ] && [ -d "$script_dir/../templates" ]; then
  templates="$(cd "$script_dir/../templates" && pwd)"
else
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  echo "Downloading templates from $TEMPLATE_REPO@$ref ..."
  gh api "repos/$TEMPLATE_REPO/tarball/$ref" > "$tmp/t.tar.gz"
  tar -xzf "$tmp/t.tar.gz" -C "$tmp" --strip-components=1
  templates="$tmp/templates"
fi

# --- copy files (never overwrite) --------------------------------------------
copy() {
  local src="$templates/$1" dst="$1"
  if [ -e "$dst" ]; then echo "  keep   $dst (already exists)"; return; fi
  echo "  create $dst"
  run mkdir -p "$(dirname "$dst")"
  run cp "$src" "$dst"
}
copy .github/workflows/patufet.yml
copy .github/workflows/patufet-mention.yml
copy .github/patufet/implement.md
copy .github/patufet/review.md
copy .claude/commands/plan-issue.md
if $with_e2e; then
  copy .github/patufet/e2e.md
  copy .github/patufet/e2e-up.sh
  copy .github/patufet/e2e-down.sh
fi

# --- fill in the caller ------------------------------------------------------
caller=.github/workflows/patufet.yml
if ! $dry_run && [ -f "$caller" ]; then
  sed -i.bak \
    -e "s|@v1$|@$ref|" \
    -e "s|language: en$|language: $language|" \
    -e "s|human-reviewer: \"\"$|human-reviewer: \"$reviewer\"|" \
    "$caller"
  if ! $with_e2e; then
    sed -i.bak '/# --- e2e (optional)/,/# --- end e2e ---/d' "$caller"
  fi
  rm -f "$caller.bak"
  sed -i.bak -e "s|@v1$|@$ref|" .github/workflows/patufet-mention.yml && rm -f .github/workflows/patufet-mention.yml.bak
fi

# --- labels ------------------------------------------------------------------
echo "Creating labels..."
run gh label create ready-to-implement --color 0E8A16 --description "Plan approved, ready for the implementer" --force
run gh label create in-progress        --color FBCA04 --description "The implementer is working on it" --force
run gh label create to-refine          --color D93F0B --description "The implementer has a question, plan needs refining" --force
run gh label create blocked            --color 5319E7 --description "Automatic run failed (quota/error)" --force
run gh label create pass               --color 0E8A16 --description "Automatic review: mergeable" --force
run gh label create warning            --color FBCA04 --description "Automatic review: fixes required" --force
run gh label create fail               --color B60205 --description "Automatic review: serious problems" --force
run gh label create needs-human-review --color 5319E7 --description "Cycle limit reached, human review needed" --force

# --- secrets -----------------------------------------------------------------
if gh secret list --json name --jq '.[].name' 2>/dev/null | grep -qE '^(CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY)$'; then
  echo "Secret found: OK"
else
  echo "WARNING: no CLAUDE_CODE_OAUTH_TOKEN / ANTHROPIC_API_KEY secret in $repo."
  echo "         Run 'claude setup-token' locally, then: gh secret set CLAUDE_CODE_OAUTH_TOKEN"
fi

cat <<MSG

Done. Next steps:
  1. Edit $caller: fill in test-command and ci-check-names.
  2. Edit .github/patufet/*.md with your project's checklist (or delete them).
$( $with_e2e && echo "  3. Adapt .github/patufet/e2e-up.sh / e2e-down.sh to start your app." )
  4. Install the Claude GitHub App on the repository if not done: https://github.com/apps/claude
  5. Commit, then open an issue and run /plan-issue <n> from Claude Code.
Docs: https://github.com/$TEMPLATE_REPO#readme
MSG
