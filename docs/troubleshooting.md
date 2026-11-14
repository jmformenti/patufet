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
full-stack issue. Defaults are now 400; raise per repository with `max-turns`. Because the
implementer commits and pushes per coherent part, re-running `workflow_dispatch` with the
same issue resumes from the branch.

**`blocked` with "no approved plan found".**
The plan comment lacks the `<!-- patufet:plan -->` marker, or its author is not a
collaborator (see security.md). For an old plan, add the marker line to the comment.

**fix-review ran but did nothing: "The PR has moved on".**
A push reached the PR after the commit this run started from. That push has its own review, which
decides again, so fixing the old report would push a stale change. Expected; nothing to do.

**`needs-human-review` with "fix-review ended without pushing a change".**
The fixer ran and pushed nothing, so no new review starts. Usual causes: it left a review point as
a question (see its comment on the PR), the report asked for no code change, or its tools were
denied (see the job log). Answer the question or fix the point and push; the push starts the next
review, and a `pass` removes the label.

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
step is over. Steps after it only get `GITHUB_TOKEN`. patufet does not need that token there: the
stages after a review are jobs of the same run, chained with `needs:` (decision 11).

**`fix-review` or `e2e` did not start after the review, although the label is there.**
They are jobs of the review's own run: look for them in the same run, next to `review`. If they
are not there, the caller predates v1.4.0. Its `fix-review` and `e2e` jobs need `needs: review`
and an `if:` on `needs.review.outputs.next-stage` (see [migration.md](migration.md)). The label
itself starts nothing, because the workflow sets it with `GITHUB_TOKEN`. A label that a person
adds does start its stage.

**The PR has no verdict label.**
A review is running (the label is removed when it starts), or it ended without a verdict, or it
found that the PR had moved on to a newer commit, whose review sets the label. If Claude finished
without a verdict, the PR also has `needs-human-review` and a comment. If the job failed before
that, was cancelled or timed out, only its log says so.

**`Newline followed by # inside a quoted argument` in the job log.**
Claude Code rejects a multi-line `gh pr comment` with a line starting with `#`. The prompts ask
for bold titles for that reason. If an extension file asks for Markdown headings in the report,
remove that: each rejected attempt spends turns.

**The review ended "waiting for agents" and posted nothing.**
Happened with the `code-review` plugin: it spawns parallel subagents and in non-interactive
CI mode the main turn ends before they report. The template uses a direct prompt and tells
the model not to launch subagents.

**`needs-human-review` with "review cycle N produced no verdict".**
Neither structured output nor a marker comment of that cycle was found: the model did not
follow the output contract (often a `max-turns` exhaustion; the job summary shows the turns).
Reports of earlier cycles are deliberately ignored. Check the log; re-run by pushing an empty
commit or re-labelling.

**The review waits until `ci-wait-timeout-minutes` on every PR.**
Some workflow that runs on pull requests takes longer than that, or never finishes: a preview
deployment, a job waiting for an approval or a runner. The review waits for every workflow of the
commit except its own; the job log of the `Wait for the CI of the commit` step and the report say
which one was still running. Raise `ci-wait-timeout-minutes`, or move that workflow to another
event. See [The CI-aware review](customization.md#the-ci-aware-review).

**The verdict is `fail` because of a workflow that is not CI.**
Every workflow that runs on pull requests counts, a linter of PR titles too. Fix it, or move it to
another event (`pull_request_target` is not waited for).

**`Invalid input, ci-checks is not defined in the referenced workflow`.**
The input was removed in v1.6.0: the review finds the CI on its own. Remove `ci-checks` from the
caller (see [migration.md](migration.md#to-v160)).

**The report says that the CI state or logs could not be read.**
The caller's `review` job lacks `actions: read`. Add it to its `permissions:`.

**`fail` with `needs-human-review` after a flaky CI failure.**
The reviewer judged the failure unrelated to the diff (`needs_human` in its result), so no
`fix-review` starts. Re-run the failed CI job, then re-run the `review` job of that push. GitHub
re-runs the jobs that need it too.

**A comment says that the reviewer returned `pass` although CI failed.**
The workflow set `fail` and `needs-human-review` and started nothing, because that report asks for
no change. Fix the cause and push, or remove and re-add `fail` to let fix-review try with the
report it has. No e2e run starts, because e2e only follows a `pass` that the workflow set.

## E2E

**The job spent 27 minutes in "Install the Playwright browser".**
`npx playwright install --with-deps` runs `apt-get update` internally and hung against a
flaky runner mirror. The template wraps it in `timeout 300` with 3 attempts. If your image
already has Chromium, set `install-playwright: false`.

**`e2e up-script not found`.**
The caller has the e2e job but the hook was not created. Either add
`.github/patufet/e2e-up.sh` (see e2e.md) or delete the `e2e` and `fix-e2e` jobs from the caller.

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

**Re-running the bootstrap did not update my caller.**
By design: it never modifies an existing file. Edit `.github/workflows/patufet.yml` by hand
(e.g. to add the e2e stage, copy the `e2e` and `fix-e2e` jobs from `templates/.github/workflows/patufet.yml`).

**Nothing runs at all.**
Check, in order: the Claude GitHub App is installed on the repository; the secret exists;
the caller's `permissions:` are at least those in security.md; the labels exist (the
bootstrap creates them, `review.yml` creates the verdict ones if missing).
