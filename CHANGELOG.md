# Changelog

## Unreleased

## v1.6.0 — 2026-11-14

- **Breaking:** the `ci-checks` input of `review.yml` is removed. It has been ignored since v1.5.0,
  and a caller that still passes it now fails with `Invalid input`: remove it (see
  `docs/migration.md`).
- A `fix-review` that ends without pushing anything (a point it left as a question, nothing it may
  change, denied tools) now labels the PR `needs-human-review` and mentions `human-reviewer`.
  Before, the PR stayed at `warning` / `fail` with no new review and nobody told.
- `implement` creates its four issue labels when they are missing, like `review` does with the
  verdict labels. Before, a renamed label that had not been created made the run fail.
- e2e: the job's `GITHUB_TOKEN` no longer reaches `e2e-up.sh`, `e2e-down.sh` or the application,
  which are code of the PR. A hook that calls `gh` must now get a token of its own.
- Internal: the steps that set the state after a review and after e2e, and the gate of
  `fix-review`, are scripts with offline tests (`apply-review-verdict.sh`, `apply-e2e-verdict.sh`,
  `fix-gate.sh`). No change in behaviour.
- Docs: removed what earlier versions left behind. `migration.md` no longer walks through the
  callers older than v1.4.0 (replace them with the template), and `customization.md` no longer
  lists the label placeholders that no workflow sets.

## v1.5.0 — 2026-11-09

- The review finds the CI of the PR's commit on its own: every workflow that runs on it for a
  `pull_request` event, except the caller's own (decision 12). A workflow left out by `paths:`
  filters is not waited for, and a renamed job needs no change.
- `ci-checks` is deprecated and ignored, with a warning in the log: remove it from the caller. The
  bootstrap no longer fills it in; it lists the workflows the review will wait for, or warns that
  there are none. `scripts/detect-ci-checks.sh` is replaced by `scripts/detect-pr-ci.sh`.
- The review's job no longer needs `checks: read`; `actions: read` is enough.
- A skipped CI job still counts as passed, but the reviewer is told that it did not run.
- With no CI on the commit, the review says so instead of only reading the diff.
- CI outside GitHub Actions is no longer waited for. See `docs/migration.md`.

## v1.4.0 — 2026-11-08

- **Breaking:** the stages after a review run in the review's own run, chained with `needs:`,
  and Claude no longer sets labels (decision 11). `review.yml` and `e2e.yml` return a new
  `next-stage` output. The caller's `fix-review` and `e2e` jobs need `needs: review` and a new
  `if:`, and a new `fix-e2e` job follows `e2e`. With an old caller the flow stops after every
  review. The new caller also works with v1.3.x, so update it first: see `docs/migration.md`.
- The verdict label is set by a deterministic step, so a stage can no longer start twice, and no
  comment ever asks to relabel a PR by hand to continue. Every stage shows in the PR's checks.
- The reviewer and the e2e tester lose `gh pr edit` (default `allowed-tools`). They only read
  and comment.
- A reviewer that finds a CI failure unrelated to the diff says so with `needs_human` in its
  structured result. The workflow then sets `fail` and `needs-human-review`, and starts no fix.
- A `pass` returned on a red CI is forced to `fail` with `needs-human-review`, and no fix starts:
  that report asks for no change. Before, it was left for a person to relabel.
- A review, e2e run or fix-review that finds the PR moved on from its commit sets no label and
  starts nothing.
- A re-run of a failed e2e puts `pass` back first, so a passing re-run says that the PR is ready.
- Fix: after a failed e2e, fix-review applies the e2e report. Before, it read only the latest
  review report, which said `pass`, so it had nothing to fix.

## v1.3.0 — 2026-11-02

- **Breaking:** removed the `test-command`, `ci-check-names` and `legacy-plan-heading` inputs, and
  `scripts/format-test-command.sh`. A caller that still passes one of them is an invalid workflow.
  The implementer and fix-review now always reproduce the CI workflows, falling back to
  `AGENTS.md` / `CLAUDE.md` / README; `ci-checks` tells the review what to wait for; a plan
  comment needs its marker. See `docs/migration.md`.
- The template and `bootstrap.sh` pass only `CLAUDE_CODE_OAUTH_TOKEN` and `ANTHROPIC_API_KEY`
  instead of `secrets: inherit`. Existing callers keep working either way; replacing it is
  recommended, see `docs/migration.md`.

## v1.2.0 — 2026-11-01

- The review can wait for the repository's CI and include its result. New `review` inputs:
  `ci-checks` (check names to wait for on the PR's head commit), `ci-wait-timeout-minutes`
  (default 30) and `human-reviewer`. A red CI means `fail`, with its cause explained from the
  failed logs; a failure unrelated to the diff asks for no code change and goes to the human
  reviewer. **Opt-in:** without `ci-checks` nothing changes. To adopt it, the caller's `review`
  job also needs `actions: read` and `checks: read`; see `docs/migration.md`.
- The `review` reusable workflow no longer declares `permissions:` and takes those of the
  caller's job. A caller with no `permissions:` on that job now fails at the Claude step instead
  of at startup. The template and the docs have always declared them.
- e2e only says "ready for merge" and mentions the reviewer if the PR is still labelled `pass`,
  because the verdict can change while it runs.
- `ci-check-names` is deprecated (kept as it was; ignored when `ci-checks` is set).
- Fix: the next stage no longer starts twice. The reviewer sometimes added the verdict label
  before removing the others and then added it again, which ran fix-review or e2e twice. The
  review now removes the verdict labels when it starts and Claude only adds one, so **a PR (not
  from a fork) has no verdict label while its review runs**, and none if the review ends without
  a verdict.
- Fix: the reviewer and the e2e tester write bold titles instead of Markdown headings, which
  Claude Code rejected in a multi-line `gh pr comment`, spending several attempts on each report.
- `test-command` is optional and no longer recommended when the repository has CI on PRs: when
  empty, the agents reproduce the CI workflows, falling back to `AGENTS.md` / `CLAUDE.md`.
- New `java-version` and `node-version` inputs on `implement` and `fix-review`, to match CI.
- `bootstrap.sh` fills in `ci-checks` from the CI jobs it detects, grants the two permissions,
  no longer generates a `test-command`, and warns when no workflow runs CI on pull requests.

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
