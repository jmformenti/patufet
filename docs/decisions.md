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

## 3. Claude applies the verdict label inside its own run

**Context.** Events created with `GITHUB_TOKEN` never trigger workflows, and the action
revokes its App token as its last step (`HTTP 401` afterwards). **Decision.** The reviewer
and the e2e tester label the PR themselves; a deterministic step compares the label with the
structured verdict and repairs it with `GITHUB_TOKEN`, saying the next stage must be
started by hand. **Consequences.** One model run per review; the tools of those agents must
allow `gh pr edit`, and the App token they use can write (see decision 7).

## 4. The workflow removes the verdict labels, Claude adds one

**Context.** GitHub emits `labeled` only when a label is really added; a combined
`--remove-label X --add-label X` does not re-fire when the verdict repeats. The reviewer first
did both, in two calls, but in real runs it sometimes added the label before removing the others
and added it again: the next stage started twice. **Decision.** `review.yml` removes the verdict
labels with `GITHUB_TOKEN` before Claude runs (which starts nothing) and the prompt asks for one
`--add-label`, so the result does not depend on the order the model follows.
`scripts/set-verdict-label.sh` keeps two calls for the repairs. e2e cannot do the same, because
its final comment needs `pass` to still be there; it goes from `pass` to `fail`, which one
combined call handles. **Consequences.** While a review runs the PR has no verdict label, and a
review that ends without a verdict leaves none, instead of the verdict of older code.

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
running app).

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
the same Claude review. `test-command` becomes optional. A new input instead of reinterpreting
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
