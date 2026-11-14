# Design decisions

Short records of the choices that shape patufet, so that nobody undoes one by accident.
Newest last.

## 1. Reusable workflows fetch their own prompts at `job.workflow_sha`

**Context.** A `workflow_call` job runs in the caller's context: `actions/checkout` and
`github.*` refer to the consumer repository, so the prompts and scripts of patufet are not on
disk. **Decision.** Each job downloads the tarball of `job.workflow_repository` at
`job.workflow_sha` into `$RUNNER_TEMP`. **Consequences.** Prompts always match the workflow
version; a fork is self-contained; the agent cannot commit them (outside the workspace). The
fetch step cannot be shared (it is what brings the scripts), so it is repeated in each
workflow. actionlint does not know these properties yet and is told to ignore them.

## 2. Labels are the state machine

**Context.** Stages must chain without a server, survive re-runs and be visible to humans.
**Decision.** Each stage is triggered by a label (`ready-to-implement`, `warning`/`fail`,
`pass`). **Consequences.** A human can move the flow by hand; label names are inputs and the
prompts receive them as placeholders; the caller's `if:` conditions are the one place a
rename must be repeated.

Since decision 11 the labels are still the state, and a label a person adds still starts its
stage, but the automatic transitions after a review are `needs:` jobs, not label events.

## 3. Claude applies the verdict label inside its own run

**Context.** Events created with `GITHUB_TOKEN` never trigger workflows, and the action
revokes its App token as its last step (`HTTP 401` afterwards). **Decision.** The reviewer
and the e2e tester label the PR themselves; a deterministic step compares the label with the
structured verdict and repairs it with `GITHUB_TOKEN`, saying the next stage must be
started by hand. **Consequences.** One model run per review; the tools of those agents must
allow `gh pr edit`, and the App token they use can write (see decision 7).

*Superseded by decision 11.*

## 4. The workflow removes the verdict labels, Claude adds one

**Context.** GitHub emits `labeled` only when a label is really added; a combined
`--remove-label X --add-label X` does not re-fire when the verdict repeats. The reviewer first
did both, in two calls, but in real runs it sometimes added the label before removing the others
and added it again: the next stage started twice. **Decision.** `review.yml` removes the verdict
labels with `GITHUB_TOKEN` before Claude runs (which starts nothing) and the prompt asks for one
`--add-label`, so the result does not depend on the order the model follows.
`scripts/set-verdict-label.sh` keeps two calls for the repairs. e2e cannot do the same, because
its final comment needs `pass` to still be there; it goes from `pass` to `fail`, which one
combined call handles, and a re-run first removes the `fail` of the previous attempt so that
fix-review starts again. **Consequences.** While a review runs the PR has no verdict label, and a
review that ends without a verdict leaves none, instead of the verdict of older code. A fork PR
keeps its label: its token is read-only, and its review fails anyway for lack of secrets. After
a re-run of a failed e2e that passes, the PR has no verdict label and the final comment says it
is not ready; adding `pass` by hand runs e2e again.

*Superseded by decision 11.*

## 5. Structured output first, marker comment as fallback, bound to the run

**Context.** Parsing free text is fragile and language-dependent; a run can end (max-turns)
after posting its report. **Decision.** `--json-schema` gives the verdict; failing that, the
`<!-- patufet:review cycle=N ... -->` / `<!-- patufet:e2e run=ID.ATTEMPT ... -->` marker of *this*
run's comment (`scripts/read-verdict.sh`). A report of an earlier run never counts, or a
failed run would inherit the previous verdict and stall the flow silently.

## 6. A direct review prompt, no `code-review` plugin

**Context.** The plugin spawns parallel subagents; in non-interactive CI the main turn ended
before they reported, and nothing was posted. **Decision.** A single-turn prompt that tells
the model not to launch subagents.

## 7. Agents' tools are narrowed to what the stage needs

**Context.** Inside the action `gh` uses the Claude App token, created with `contents`,
`pull_requests` and `issues` **write** whatever the job's `permissions:` say
(claude-code-action `src/github/token.ts`). **Decision.** The reviewer and the e2e tester
only get `gh pr view|diff|comment|edit` and `gh issue view` (no `gh api`, no `gh pr merge`);
the implementer and fixer get `Bash` because they must run tests and git. **Consequences.**
`gh pr edit` cannot be limited to labels by prefix: those agents can still change the PR's
title, body, base branch and reviewers, not merge or push. Widening `allowed-tools` on
review / e2e gives write access to an agent that reads untrusted content (the diff, the
running app). Since decision 11 those two agents no longer label, and they lost `gh pr edit`.

## 8. Only trusted text reaches an agent that can write

**Decision.** Plans come from collaborators only; review reports and inline comments from
collaborators or the automation bots (`scripts/trusted-comments.jq`). The plan gate means a
human has read anything derived from an issue body before an agent with write access acts
on it. See [security.md](security.md).

## 9. Third-party actions pinned by major tag, tools by exact version

**Context.** Consumers themselves follow `patufet@v1`, a moving tag. **Decision.**
`actions/checkout@v6` and `anthropics/claude-code-action@v1` follow their major tag, like
patufet does, so fixes arrive without a release; tools fetched at run time
(`@playwright/mcp`, the Playwright browser, actionlint) are pinned to exact versions, because
they have broken runs before and do not follow semver. **Consequences.** A compromised major
tag of those two actions would reach consumers; pin them by SHA in a fork if that risk
matters more than the updates.

## 10. The repository's CI is the source of truth; the review waits for it in `pull_request`

**Context.** `test-command` copied each repository's CI by hand and drifted from it, and the
review ran in parallel with CI, so a PR could get `pass` while its CI ended red. **Decision.**
The review job polls the checks named in `ci-checks` and gives their result and failed logs to
the same Claude review. `test-command` became optional and was removed in v1.3.0, once the
consumers had migrated. A new input instead of reinterpreting
`ci-check-names`: that one holds free text, which would never match a check and would make every
review wait until the timeout.

**Rejected.** `workflow_run` on CI completion: it runs with secrets and a write token even for
fork PRs ("pwn request"), cannot be tested before merge and does not show in the PR checks.
Calling the CI as a reusable workflow from the caller: it couples CI to patufet, renames its
checks and can run it twice. A separate bash path for red CI that labels without Claude: it needs
the App token outside Claude and a new comment format for `fix-review`.

**Consequences.**

- The review job declares no `permissions:`, unlike the other reusable workflows. A called
  workflow can only reduce what its caller grants, so declaring `actions: read` would ask more
  than a caller that has not opted in grants, and leaving it out of a declared list would deny it
  to the one that has. A caller with no `permissions:` on that job now gets the repository's
  default token rather than a bounded one (and no `id-token`, so Claude fails). The template
  declares them, and `tests/run.sh` checks both sides.
- The logs are read per job (`actions/jobs/<id>/logs`), not with `gh run view --log-failed`, which
  refuses while any other job of the run is still in progress.
- The issue's `--required` idea was left out: `ci-checks` is explicit and works without branch
  protection.

*Since decision 12 the review finds the CI on its own: `ci-checks` is no longer read.*

## 11. Stages chain with `needs:` inside one run; Claude never sets the state

**Status.** Accepted on 2026-11-08, implemented for v1.4.0. It supersedes decisions 3 and 4
and narrows decision 7.

**Context.** Two GitHub rules shape the chaining. Events created with `GITHUB_TOKEN` start no
workflow run, and a run shows in a PR's checks only when a PR event started it. Today only the
Claude App token, alive inside the Claude step, can create a PR event that starts the next
stage, so the model sets the verdict label (decisions 3 and 4). That costs a repair path, which
asks a human to relabel when the model did not label, a transient `pass` that can start e2e on a
red CI, a double start when the model labelled twice (fixed in v1.2.0), and `gh pr edit` in the
tools of agents that read untrusted content. One criterion was wanted for every transition, with
no workaround.

**Decision.** The labels stay the state, but only deterministic steps write them, and the stages
that follow a review run in the same run.

- `fix-review` and `e2e` are jobs of the caller's `pull_request` run, with `needs: review` and an
  `if:` on the verdict that `review.yml` returns as a `workflow_call` output. A failed e2e is
  followed by a second `fix-review` job with `needs: e2e`.
- Claude returns the verdict (structured output, or the marker of this run's comment, see
  decision 5) and posts its comments. It never adds or removes a label. A deterministic step sets
  the verdict label with `GITHUB_TOKEN`, as state for humans; it starts nothing, so a stage
  cannot start twice.
- Transitions that create code stay events of the Claude App token: the implementer opens the PR
  (`opened`) and `fix-review` pushes (`synchronize`), which starts the next review.
- People keep moving the flow by hand. A label they add starts its stage alone in a run of its
  own (`labeled`), and a push starts a review.
- `fix-review` does nothing when the PR head is no longer the commit its run started from.
- The review still waits for CI by polling (decision 10).

**Rejected.**

- A GitHub App of patufet's own, to get a token whose events start workflows. A private app
  means two secrets per repository, a `bot-login` input and a period where both bots are
  trusted. It can only be installed on the account that owns it, so not on an organisation's
  repository, and every new permission becomes a manual step for every adopter. A public app
  needs a server that holds a key to every installation and exchanges OIDC tokens. Chainguard's
  `octo-sts` offers that service, but its app asks for admin-level write permissions. In about
  31 reviewed PRs across the three consumers, no stage ever had to be restarted by hand.
- A deterministic step that starts the next stage with `workflow_dispatch`, the one event
  `GITHUB_TOKEN` may create. It works, but the dispatched run does not show in the PR. The PR
  shows the stage as skipped by the `pull_request` run instead, which is misleading. Check runs or
  commit statuses could make it visible, but they stay pending forever when a job dies, and they
  duplicate the label state.
- A label set by CI, or by a Claude run at the end of CI, to start the review. A label set with
  `GITHUB_TOKEN` starts nothing, and a model run just to obtain a token is costly and may not
  label. `workflow_run`, and CI inside patufet's run, were already rejected in decision 10.

**Evidence.** Spikes on the sandbox repository, run on 2026-11-08 with a local reusable workflow:

- A `needs:` job can branch on a reusable workflow's output, two levels deep, and every job
  shows in the PR's checks.
- Labels added or removed with `GITHUB_TOKEN` created no run.
- A push during `fix-review` did not cancel it, and the new run's fix job waited for it
  (`cancel-in-progress: false`).
- Two quick pushes cancelled the first review, and the jobs that needed it were skipped.

Not tested: a reusable workflow called from another repository, which is how consumers use
patufet.

**Consequences.**

- The caller changes, so it is a breaking change. Following CONTRIBUTING.md, it ships as a
  minor marked **Breaking** once the three consumers are migrated; otherwise it needs `v2`. The
  PRs that edit `patufet.yml` must be merged by hand (see troubleshooting.md).
- What goes away: the label repair, the comments asking to relabel by hand, and `gh pr edit` in
  the review and e2e tools. `review.yml` still removes the verdict labels before Claude runs, now
  only so that the PR never shows the verdict of older code.
- One run holds the review and the stages that follow it. "Re-run failed jobs" works within
  that run.
- The PR's checks still list skipped jobs, as they do today.

**Update, v1.7.0.** The chain (`needs:` and `if:`) moved from each consumer's caller into
`pull-request.yml`, a reusable workflow that calls `review.yml`, `fix-review.yml` and `e2e.yml`
with `uses: ./...`. GitHub resolves that path at the commit of `pull-request.yml` itself, and
`job.workflow_sha` and `github.workflow_ref` keep their values one level deeper (decisions 1 and
12 hold; tried on the sandbox, issue #21). The caller has one job, the `if:` conditions read the
`label-*` inputs instead of literal names, and changing the chain no longer changes the callers.
The cost: longer check names (`pull-request / review / review`) and a caller job that grants
`contents: write`, which each stage then narrows.

## 12. The review finds the CI of the commit; no `ci-checks`

**Status.** Accepted on 2026-11-08, for v1.5.0. It amends decision 10: the review still waits for
CI by polling, but no longer by name.

**Context.** `ci-checks` listed the names of the checks to wait for. They had to match exactly, a
matrix or a reusable workflow had to be added by hand, a workflow left out by `paths:` filters made
every review wait until the timeout, and a renamed job went stale without anybody noticing. In the
three consumers, `ci-checks` was exactly the list of jobs of the only workflow that runs on pull
requests.

**Decision.** The CI of a commit is every workflow run that GitHub started for it on a
`pull_request` event, except the caller's own workflow, whose path comes from
`github.workflow_ref` (`scripts/wait-for-ci.sh`). When a workflow ran more than once on the
commit, its latest run counts. Its jobs are the checks, and the reviewer gets their result and the
logs of the failed ones. With no such run, after one more look, the review starts at once.
`ci-checks` is ignored with a warning, and the bootstrap only warns when nothing runs CI on pull
requests (`scripts/detect-pr-ci.sh`).

*In v1.6.0 the input was removed, once no known caller passed it.*

**Rejected.**

- Keeping `ci-checks` as an override. No consumer needed it, and it is the source of the errors
  above.
- An exclusion list (`ci-ignore`). No consumer has a non-CI workflow on pull requests. It can be
  added if one ever needs it.
- The required status checks of the branch rules. Most repositories have none, and reading a
  classic branch protection needs admin rights.
- Waiting for check runs or commit statuses of other apps. Their names would have to be configured
  again, and their logs cannot be read.

**Evidence.** A spike on the sandbox repository on 2026-11-08:

- The CI run already existed when a workflow of the same event started.
- Filtering by event and leaving out the own workflow found exactly `ci.yml`, both green and red.
- The failed job's log could be read with `actions: read`, on a private repository, without
  `checks: read`.

**Consequences.**

- Nothing to configure, and `checks: read` is no longer needed.
- Every workflow on pull requests is waited for, even one that is not CI: a slow one delays the
  review, and a failing one makes it `fail`.
- CI outside GitHub Actions is no longer waited for. With `ci-checks` it could be, with limits.
- A job skipped on the commit counts as passed, but the reviewer is told that it did not run.

