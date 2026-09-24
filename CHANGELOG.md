# Changelog

## Unreleased

## v1.1.0 — 2026-09-23

First release under the name patufet (`v1.0.0` still carries the `agentic-sdlc` names).
Fixes and changes from a technical review of the repository:

- **Security:** the reviewer and the e2e tester no longer get `Bash(gh api:*)` /
  `Bash(gh pr *)` by default, only `gh pr view|diff|comment|edit` and `gh issue view`. Inside
  the action `gh` uses the Claude App token, which has `contents`/`pull_requests`/`issues`
  write regardless of the job permissions: the old defaults let an agent that reads
  untrusted content write to the repository or merge the PR. If you set `allowed-tools`
  yourself on those jobs, review it. `docs/security.md` documents the token.
- Fix: renamed labels (`label-*` inputs) now reach the review and e2e prompts; before,
  Claude labelled with the default names and the flow stopped. `/plan-issue` reads the ready
  label from the caller.
- Fix: when a review has no structured output, only the report of *that* cycle counts. A run
  that failed without posting used to inherit the previous verdict and stall the PR
  silently; it now labels `needs-human-review`. Same for e2e, whose marker gains
  `run=<run_id>.<attempt>` and whose fallback now ignores untrusted comments.
- Fix: `bootstrap.sh` no longer edits an existing caller (re-running it without `--with-e2e`
  deleted the e2e job). It prints its usage when run through `bash <(curl …)`, rejects
  options without a value (or with another option as value) and writes `--language` /
  `--reviewer` as YAML strings, so free text like `Catalan: Valencian` stays valid.
- Fix: review no longer recreates the verdict labels with `--force` (it overwrote their
  colour on every run) and creates the missing ones *before* Claude needs them.
- Fix: fix-review gets only the inline comments that are not outdated, and pushes once at
  the end instead of after each part (each push started a review and could spend cycles).
- Fix: implement no longer posts two comments when there is no plan, and only an open PR
  counts as the run's result. e2e tests the commit that got `pass`, not a later push, and
  only announces "ready for merge" if the PR is still at that commit. The mention caller no
  longer re-runs on `issues: assigned`.
- Fix: the fallback verdict requires the exact marker and value (`patufet:review-notes` or
  `verdict=passed` count neither as a verdict nor as a cycle). Review fails visibly if a
  verdict label cannot be created.
- Fix: a `{{ x }}` in a consumer's extension file (Vue, Handlebars) is kept verbatim;
  `Closes: #N`, extra spaces and `owner/repo#N` (same repository) now link a PR to its issue.
- Workflow logic moved to scripts (`gather-context.sh`, `plan-section.sh`, `read-verdict.sh`,
  `format-test-command.sh`, `ensure-labels.sh`, `github-output.sh`); prompts are written to
  `GITHUB_OUTPUT` with a random delimiter.
- New: every job writes a summary with outcome, turns, duration and reported cost.
- New input `playwright-mcp-version` (e2e, default `0.0.82`); the Playwright browser now
  matches the version the MCP server uses. actionlint is pinned in self-check.
- Caller template: `test-command` is written once and reused by fix-review through a YAML
  alias. Existing callers are unchanged.
- Tests: `tests/run.sh`, offline tests of the scripts, the bootstrap and the consistency of
  prompts, workflows and docs, run by `self-check.yml`.
- Docs: `AGENTS.md` is now for agents working on patufet; the adoption runbook moved to
  `ADOPTING.md` (the old raw URL of `AGENTS.md@v1` now points adopters there).
  New `CONTRIBUTING.md` (testing, releasing, rolling back) and `docs/decisions.md`. Input
  tables corrected; the README bootstrap command uses `v1`, not `main`.

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
- Docs: new `ADOPTING.md`, an adoption runbook for coding agents (preconditions, bootstrap,
  what to fill in, verification, and the steps only a human can do). Linked from the README
  quick start with a ready-to-paste prompt.
- `bootstrap.sh` no longer overwrites labels that already exist (it used `--force`): they are
  kept untouched with a warning, since they may mean something else in the repository. It also
  warns when an existing workflow already uses `anthropics/claude-code-action`, which would run
  alongside patufet. `ADOPTING.md` gained an "Existing automation" section covering these and
  the other collisions (labelling bots, branch rulesets, CI that skips bot PRs).
- `ADOPTING.md`: the adoption always ends in a pull request whose body is the hand-over report
  (what was inferred, conflicts found, checks run, human steps pending); direct commits only
  on the owner's explicit request.
- Docs: `docs/uninstall.md`, one uninstall procedure for humans and agents (in-flight work,
  files, only the labels created for patufet, secret and App).
- Docs: README "TL;DR" with the three prompts (adopt with an agent, run one issue with
  `/plan-issue`, uninstall with an agent).

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
