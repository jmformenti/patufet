# Changelog

## Unreleased

- **Breaking:** renamed the project from `agentic-sdlc` to `patufet`. Everything that carried
  the old name changes: repository (`jmformenti/patufet`, GitHub redirects the old URL),
  comment markers (`<!-- patufet:plan -->`, `<!-- patufet:review ... -->`,
  `<!-- patufet:e2e ... -->`), the consumer directory `.github/patufet/`, the `PATUFET_*`
  variables, the caller file names (`patufet.yml`, `patufet-mention.yml`) and the concurrency
  groups. Existing plan comments with the old marker are not recognised any more: re-post the
  plan, or add the new marker line to the comment.
- Defaults raised to the values habitus-trainer settled on: `max-turns` 400 for implement,
  review and fix-review (review was 100, the others 200), 200 for e2e (was 100), and
  `max-review-cycles` 10 (was 3). The template caller now also sets `max-review-cycles: 10`.
- Docs: the flow and state-machine diagrams in `README.md` and `docs/architecture.md` are now
  Mermaid instead of ASCII art.

## v1.0.0 — 2026-09-05

First release, extracted from the `habitus-trainer` autonomous flow. Briefly published the
same day under the name `claude-sdlc`; renamed to `agentic-sdlc` (repository, markers,
`.github/agentic-sdlc/` directory, `AGENTIC_SDLC_*` variables, caller file names, default
branch prefix `agent/issue-`) to respect Anthropic's trademark guidelines, and the release
re-tagged. Nothing consumed the earlier name except habitus-trainer, migrated in the same day. Compared to the
original copied workflows:

- Reusable workflows (`workflow_call`) with inputs; prompts and helpers fetched from this
  repository at the exact executing commit.
- Prompts in English, `language` input for the text Claude writes.
- Machine-readable markers (`<!-- agentic-sdlc:plan -->`, `<!-- agentic-sdlc:review ... -->`,
  `<!-- agentic-sdlc:e2e ... -->`) instead of language-bound headings.
- Verdict from structured output + deterministic labelling (one Claude run per review
  instead of two).
- Trust filter on plans, review reports and inline comments (author association / bot).
- Conservative defaults: `max-review-cycles: 3`, `max-turns` 100–200.
- Draft PRs are not reviewed until marked ready.
- E2E stage generalised through `e2e-up.sh` / `e2e-down.sh` hooks.
- `bootstrap.sh` installer, `self-check.yml` lint.
