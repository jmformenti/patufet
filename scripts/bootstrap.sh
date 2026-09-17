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
#   3. creates the 8 flow labels (existing ones are left untouched, with a warning);
#   4. checks that CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY is set;
#   5. warns about workflows that already use anthropics/claude-code-action.
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

# --- existing automation ----------------------------------------------------
# Another workflow on claude-code-action (the action's own @claude / review
# examples) would answer the same events twice: two replies per mention, two
# reviews per push, twice the cost.
existing=$(grep -lE 'anthropics/claude-code-action' .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null || true)
if [ -n "$existing" ]; then
  echo "WARNING: these workflows already use anthropics/claude-code-action and will run alongside patufet:"
  echo "$existing" | sed 's/^/         /'
  echo "         Remove them, or delete .github/workflows/patufet-mention.yml if you only want their @claude handling."
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
# The flow reacts to these names (see the caller's `if:`). A label that already
# exists is left as it is: it may carry another meaning in this repository, in
# which case rename patufet's through the `label-*` inputs instead.
echo "Creating labels..."
existing_labels=$(gh label list --limit 1000 --json name --jq '.[].name' 2>/dev/null || true)
label() {
  local name="$1" color="$2" description="$3"
  if grep -qxF "$name" <<<"$existing_labels"; then
    echo "  keep   $name (already exists, left untouched)"
    return
  fi
  echo "  create $name"
  run gh label create "$name" --color "$color" --description "$description"
}
label ready-to-implement 0E8A16 "Plan approved, ready for the implementer"
label in-progress        FBCA04 "The implementer is working on it"
label to-refine          D93F0B "The implementer has a question, plan needs refining"
label blocked            5319E7 "Automatic run failed (quota/error)"
label pass               0E8A16 "Automatic review: mergeable"
label warning            FBCA04 "Automatic review: fixes required"
label fail               B60205 "Automatic review: serious problems"
label needs-human-review 5319E7 "Cycle limit reached, human review needed"
if [ -n "$existing_labels" ] && grep -qxE 'ready-to-implement|in-progress|to-refine|blocked|pass|warning|fail|needs-human-review' <<<"$existing_labels"; then
  echo "WARNING: some flow labels already existed. If they mean something else here, rename patufet's"
  echo "         with the label-* inputs and update the caller's if: conditions (docs/customization.md)."
fi

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
