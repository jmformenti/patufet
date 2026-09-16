# Troubleshooting

Failure modes met while building and running the original flow, and what the template does
about them. When something new happens, read the job log with `show-full-output: true` first.

## Implement / fix-review

**The run is green but nothing happened (no PR, no commits).**
Cause seen: `--allowedTools` missing → the action denied every `Bash` call (18 denials in
one run) and the agent could not run git or tests. The template always passes
`--allowedTools` (`allowed-tools` input) and fails the job when no PR / `to-refine` results.

**The run hit `max-turns` mid-way.**
100 turns were short for a medium issue; one run used 193 for the frontend half of a
full-stack issue. Defaults are 200; raise per repository with `max-turns`. Because the
implementer commits and pushes per coherent part, re-running `workflow_dispatch` with the
same issue resumes from the branch.

**`blocked` with "no approved plan found".**
The plan comment lacks the `<!-- patufet:plan -->` marker, or its author is not a
collaborator (see security.md). For old issues use `legacy-plan-heading`.

**The agent's push did not trigger the review.**
Events created with `GITHUB_TOKEN` never trigger workflows. The action pushes with its own
App token, which does. If you changed the checkout / credential setup, restore
`persist-credentials: false` + `gh auth setup-git`.

## Review

**Two review runs for one push / stale review labelled after a newer one.**
`review.yml` uses `cancel-in-progress: true` per PR. If you copied the job elsewhere, keep
the concurrency group.

**`HTTP 401: Bad credentials` when using `steps.claude.outputs.github_token`.**
The action revokes its App token as its last internal step, so the output is dead once the
step is over. Anything that must trigger another workflow (labelling) has to happen inside
the Claude run; steps after it only get `GITHUB_TOKEN`.

**`fix-review` did not start after a `warning` although the label is there.**
The verdict was the same as the previous cycle and the label was added/removed in a single
`gh pr edit` call, so GitHub emitted no new `labeled` event. `scripts/set-verdict-label.sh`
always does two separate calls; if the label step used `GITHUB_TOKEN` instead of the App
token the event would not trigger anything either.

**The review ended "waiting for agents" and posted nothing.**
Happened with the `code-review` plugin: it spawns parallel subagents and in non-interactive
CI mode the main turn ends before they report. The template uses a direct prompt and tells
the model not to launch subagents.

**`needs-human-review` with "produced no verdict".**
Neither structured output nor a marker comment was found: the model did not follow the
output contract (often a `max-turns` exhaustion). Check the log; re-run by pushing an empty
commit or re-labelling.

## E2E

**The job spent 27 minutes in "Install the Playwright browser".**
`npx playwright install --with-deps` runs `apt-get update` internally and hung against a
flaky runner mirror. The template wraps it in `timeout 300` with 3 attempts. If your image
already has Chromium, set `install-playwright: false`.

**`e2e up-script not found`.**
The caller has the e2e job but the hook was not created. Either add
`.github/patufet/e2e-up.sh` (see e2e.md) or delete the job from the caller.

**The app registers a user then gets 403.**
Project-specific readiness/seeding logic belongs to your hook; make it idempotent and
tolerant to data the app seeds on its own (the original project started seeding an admin
on empty DB, and the hook had to fall back to those credentials).

## Any PR that changes the caller workflow file

The Claude action skips itself with "Workflow validation failed. The workflow file must
exist and have identical content to the version on the repository's default branch". This
is the action's own protection on `pull_request`-triggered runs: it refuses to run from a
workflow file that differs from the one on the default branch. It happens on the PR that
first adds `patufet.yml` **and on every later PR that edits it** (bumping `@v1`,
changing an input...). Expected behaviour: the review job fails with an explicit error, no
label and no comment; merge such PRs by hand after the normal CI is green. Everything works
again from the next PR.

## General

**"context runner is not allowed here".**
`runner.temp` is not available at job-level `env` in reusable workflows; the template
exports `TPL_DIR` from a step via `$GITHUB_ENV`.

**actionlint reports `job.workflow_repository` / `job.workflow_sha` as undefined.**
They are documented GitHub context properties (workflow identity for reusable workflows)
that actionlint does not know yet; `self-check.yml` ignores exactly that message.

**Nothing runs at all.**
Check, in order: the Claude GitHub App is installed on the repository; the secret exists;
the caller's `permissions:` are at least those in security.md; the labels exist (the
bootstrap creates them, `review.yml` recreates the verdict ones).
