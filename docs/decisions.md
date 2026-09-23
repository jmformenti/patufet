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

## 4. Two `gh pr edit` calls per verdict

**Context.** GitHub emits `labeled` only when a label is really added; a combined
`--remove-label X --add-label X` does not re-fire when the verdict repeats. **Decision.**
Remove all verdict labels, then add one, in separate calls (prompts and
`scripts/set-verdict-label.sh`).

## 5. Structured output first, marker comment as fallback, bound to the run

**Context.** Parsing free text is fragile and language-dependent; a run can end (max-turns)
after posting its report. **Decision.** `--json-schema` gives the verdict; failing that, the
`<!-- patufet:review cycle=N ... -->` / `<!-- patufet:e2e run=ID ... -->` marker of *this*
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
Widening `allowed-tools` on review / e2e gives write access to an agent that reads untrusted
content (the diff, the running app).

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
