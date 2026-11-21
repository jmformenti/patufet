# Customization

Three layers, from cheapest to deepest:

1. **Inputs** of the caller workflow (`with:`) — language, limits, labels, model.
2. **Prompt extension files** in the consumer repository — project knowledge appended to the
   base prompts.
3. **Forking** this repository — only if you need to change the base prompts or the flow.
   `job.workflow_repository` makes a fork self-contained: callers just point `uses:` at it.

## 1. Inputs

Every input also has a `description:` in its workflow, shown by GitHub when editing the
caller.

The caller has two jobs: `implement` (an issue) and `pull-request` (a pull request), which runs
`review`, `fix-review` and `e2e` as its own jobs. The tables below describe the inputs stage by
stage; [`pull-request`](#pull-request) says under which name the caller sets each one.

Common to `implement`, `review`, `fix-review`, `e2e`:

| Input | Default | Notes |
|---|---|---|
| `language` | `en` | Language of the comments / PR descriptions Claude writes. Free text or ISO code. Code and commit messages follow the repository conventions, not this. |
| `model` | per stage, see [Models](#models) | Passed as `--model`. |
| `max-turns` | 400 (implement, review, fix-review) / 200 (e2e) | Hard cap on agent turns. |
| `allowed-tools` | per workflow | `--allowedTools`. Implementer and fixer get `Bash,Edit,Write,Read,Glob,Grep`; reviewer and e2e tester only `gh pr view/diff/comment`, `gh issue view` and their read / MCP tools (they do not label: the workflow does). Inside the action `gh` uses the Claude App token, which **can write**: widen these two only knowing that (see [security.md](security.md)). |
| `claude-args-extra` | `''` | Anything else for `claude_args`. |
| `show-full-output` | `true` | Full transcript in the job log. Needed to diagnose tool denials; may echo secrets printed by tools. |
| `extra-instructions-file` | `.github/patufet/<stage>.md` | See layer 2. |
| `timeout-minutes` | 45 (implement, fix-review) / 30 (review, e2e) | Job timeout. On `review` it bounds the Claude step only: the wait for CI has its own limit. |

`implement`:

| Input | Default | Notes |
|---|---|---|
| `issue-number` | *(required)* | The caller passes `fromJSON(inputs.issue \|\| github.event.issue.number)`. |
| `branch-prefix` | `agent/issue-` | Branch = prefix + issue number. Also used by review/e2e to find the linked issue. |
| `java-version`, `node-version` | `''` | Set up that version on the runner (`actions/setup-java` with Temurin, `actions/setup-node`) so that it matches CI. Empty = what `ubuntu-latest` brings. Also on `fix-review`. |
| `label-ready`, `label-in-progress`, `label-to-refine`, `label-blocked` | `ready-to-implement`, `in-progress`, `to-refine`, `blocked` | See [Renaming the labels](#renaming-the-labels). |

`review`:

| Input | Default | Notes |
|---|---|---|
| `ci-wait-timeout-minutes` | `30` | Maximum wait for the CI of the commit. When it ends, the review runs and reports that CI has not finished. See [The CI-aware review](#the-ci-aware-review). |
| `human-reviewer` | `''` | Login (no `@`) mentioned when a CI failure needs a person: it is unrelated to the diff, or the workflow had to force `fail` over a `pass`. |
| `branch-prefix` | `agent/issue-` | Same as implement, to find the linked issue. |
| `allowed-bots` | `claude` | The implementer opens PRs as the `claude` bot; without this the action refuses bot-triggered events. Also on `fix-review` and `e2e`. |
| `label-pass`, `label-warning`, `label-fail`, `label-needs-human-review` | `pass`, `warning`, `fail`, `needs-human-review` | Created if missing (existing labels are never modified). |

Outputs: `verdict` (the label set: `pass` / `warning` / `fail`, empty when none) and `next-stage` (`fix-review` / `e2e`, empty when none), which the `fix-review` and `e2e` jobs of `pull-request.yml` read with `needs: review`. `e2e` returns the same two (`next-stage=fix-review` on a failure, for `fix-e2e`).

`fix-review`:

| Input | Default | Notes |
|---|---|---|
| `max-review-cycles` | `10` | Reports before handing over to a human. |
| `human-reviewer` | `''` | Login (no `@`) mentioned when the limit is reached, or when the fix ends without a push. |
| `label-needs-human-review` | `needs-human-review` | Set when the limit is reached, or when the fix ends without a push. Created if missing. |

`e2e`: see [e2e.md](e2e.md) (`label-pass`, `label-warning`, `label-fail` as in review).

`mention`: `model`, `claude-args-extra`, `timeout-minutes`.

### Models

With `model` empty, each stage runs with the model patufet chooses for it:

| Stage | Default model | Why |
|---|---|---|
| `implement` | `claude-opus-5-5` | The most open work, from an issue to working code. A better first version saves fix cycles. |
| `review` | `claude-opus-5-5` | The quality gate: a bug it misses costs more than the difference in price. |
| `fix-review` | `claude-sonnet-5-5` | Concrete findings to apply, and it can run up to `max-review-cycles` times. Also `fix-e2e`. |
| `e2e` | `claude-sonnet-5-5` | Many tool calls and page snapshots: volume more than reasoning. |
| `mention` | `claude-sonnet-5-5` | Ad-hoc requests; set `model` for heavier ones. |

On a subscription (`CLAUDE_CODE_OAUTH_TOKEN`) a larger model uses the usage limit faster; with
an API key it costs more per token. Claude Code may still use a small model for its own
auxiliary tasks; patufet does not set that one.

In `pull-request`, `review-model`, `fix-model` and `e2e-model` set one stage; `model` sets every
stage left empty. An empty value at both levels leaves the stage's default.

### `pull-request`

`pull-request.yml` runs the three stages above and passes every one of their inputs on, with the
same defaults (`tests/run.sh` checks it). The rule for the names:

| Input of `pull-request` | Goes to |
|---|---|
| `e2e` (default `false`) | Turns the live e2e stage on. With `false` the flow ends at the review's `pass`. |
| `language`, `human-reviewer`, `branch-prefix`, `allowed-bots`, `claude-args-extra`, `show-full-output`, `label-pass`, `label-warning`, `label-fail`, `label-needs-human-review` | The input of the same name of every stage that has it. One value for the whole pull request. |
| `model` | `model` of every stage whose own input below is empty |
| `review-model`, `fix-model`, `e2e-model` | `model` of `review`, `fix-review` (and `fix-e2e`), `e2e`; empty = `model` |
| `ci-wait-timeout-minutes` | `review` |
| `max-review-cycles`, `java-version`, `node-version` | `fix-review` (and `fix-e2e`, which is the same workflow) |
| `install-playwright`, `playwright-mcp-version` | `e2e` |
| `review-extra-instructions-file`, `review-max-turns`, `review-allowed-tools`, `review-timeout-minutes` | `review`, without the prefix |
| `fix-extra-instructions-file`, `fix-max-turns`, `fix-allowed-tools`, `fix-timeout-minutes` | `fix-review` and `fix-e2e`, without the prefix |
| `e2e-up-script`, `e2e-down-script`, `e2e-extra-instructions-file`, `e2e-max-turns`, `e2e-allowed-tools`, `e2e-timeout-minutes` | `e2e`, without the prefix |

To change more than the inputs allow (other permissions, conditions or jobs), call `review.yml`,
`fix-review.yml` and `e2e.yml` as separate jobs of the caller, as the callers older than v1.7.0
do. Take the four jobs of `pull-request.yml` with their `needs:`, `if:` and `permissions:`, and
change three things, since they are written to run inside patufet:

- `uses: ./.github/workflows/review.yml` becomes
  `uses: jmformenti/patufet/.github/workflows/review.yml@v1` (a `./` path in your caller would
  point at your own repository);
- every `${{ inputs.x }}` under `with:` becomes your value, or goes away to keep the default;
- in the `if:` conditions, `inputs.label-warning`, `inputs.label-fail` and `inputs.label-pass`
  become the literal names (`'warning'`, `'fail'`, `'pass'`), and `inputs.e2e &&` goes away:
  without e2e, leave the `e2e` and `fix-e2e` jobs out.

The caller's job must grant `contents: write`, `pull-requests: write`, `issues: read`,
`id-token: write` and `actions: read`. A job of a reusable workflow cannot get more than its
caller grants, and each stage declares only what it needs: `review` and `e2e` run with
`contents: read`.

### How the review reads the diff

A large `gh pr diff` reaches the agent only as a short preview of a file Claude Code saved, and
the reviewer then tends to review the preview. So the workflow cuts the diff into parts
(`scripts/diff-section.sh`). Each file becomes one or more parts of at most 600 lines and 20 KB,
cut between hunks where it can; a part cut inside a hunk is listed with the old and new line
where it starts, so the inline comments land on the right line. The prompt lists every part, and the agent reads them with
`Read` (it gets `--add-dir` for the directory of the parts).

Lockfiles (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `*.lock`), minified or generated
files (`*.min.*`, `*.map`, `*.snap`) and binaries are listed but not expected to be read.

After the review, `scripts/diff-coverage.sh` counts the parts the agent opened: with `Read`, or
with a Bash command such as `cat` that names them, when those parts fit together in the 30 000
characters of Bash output Claude Code shows whole (a call that failed or was denied reads
nothing). The job summary
shows `Diff read: X of Y parts`. When some part was not read, a comment on the PR names its
files: **the verdict does not change**, it only tells the person who merges what to check by hand.
Keep `Read` in `allowed-tools`: the prompt asks for one `Read` per part, and without it only the
parts read with a Bash command count.

### The CI-aware review

The repository's own CI is the single source of truth for build and test. The review finds it on
its own and waits for it before reviewing (decision 12). **There is nothing to configure.**

**What counts as CI:** every workflow that GitHub starts for the PR's head commit on a
`pull_request` event, except the caller's own (`patufet.yml`). Their jobs are the checks. So:

- a workflow that its `paths:` or `branches:` filters leave out of a PR does not run, and the review
  does not wait for it;
- a job that is added or renamed is waited for without editing anything;
- workflows on other events (`push`, `pull_request_target`, `workflow_run`, comments) are not CI
  of the PR, and neither is the mention workflow, which runs on comments. Another Claude workflow
  that runs on `pull_request` is waited for: remove it (see [ADOPTING.md](../ADOPTING.md));
- with no such workflow at all, the review starts right away and says that no CI ran.

| CI | What the reviewer gets | Verdict |
|---|---|---|
| green | the names of the jobs that passed | on the merits of the diff |
| red | the failed jobs and the end of their logs | always `fail`, with the cause explained inline where possible; `fix-review` applies it. If the workflow sees `pass` here, it forces `fail` |
| red, unrelated to the diff (runner, network, flaky test) | same | still `fail`, but it asks for no code change, mentions `human-reviewer` and adds `needs-human-review`; no `fix-review` starts |
| not finished at the timeout (`ci-wait-timeout-minutes`) | the state of each job | on the merits of the diff; the report says that it does not vouch for those jobs |
| none on the commit | that no CI ran | on the merits of the diff |
| unreadable (no permission) | that it could not be read | same; the report says which permission is missing |

A skipped job or workflow counts as passed. When a workflow ran more than once on the same
commit (an earlier event, a re-run), its latest run counts.

**Every workflow that runs on pull requests is waited for**, also one that is not really CI: a
preview deployment makes the review wait longer, and a failing linter of PR titles makes the
verdict `fail`. If that is a problem, move such a workflow to another event or open an issue.

**CI outside GitHub Actions** (Jenkins, CircleCI, Buildkite...) is not waited for: the review only
sees GitHub Actions workflows. Its result does not reach the reviewer, and a red external CI does
not make the verdict `fail`. The implementer and fix-review only reproduce the workflows in
`.github/workflows/`, so make sure `AGENTS.md`, `CLAUDE.md` or the README describe how to build and
test.

**The caller's `review` job needs `actions: read`**, to list the runs of the commit and read the
logs of the failed jobs:

```yaml
permissions:
  contents: read
  pull-requests: write
  issues: read
  id-token: write
  actions: read # the CI runs of the commit and the logs of failed jobs
```

Without it the state of CI cannot be read: the review goes on and its report asks you to add it.
`checks: read` is no longer needed.

**Cost:** the review's runner idles while CI runs (billable minutes on private repositories),
and a red CI still spends a Claude review, which in return gives `fix-review` an explanation
instead of raw logs.

Re-running a failed CI job does not start a new review, because no event reaches `patufet.yml`.
After a flaky failure, re-run the CI job and then the `review` job of the same push. GitHub
re-runs the jobs that need it too.

### Renaming the labels

Rename when a flow label already means something else in the repository (a project board's
`blocked`, a bot's `pass`...). All in the caller, in the consumer repository:

1. the verdict labels: the `label-*` inputs of the `pull-request` job, and nothing else. The
   workflow sets them and starts the stage a person asks for with one from those values;
2. the issue labels: the `label-*` inputs of the `implement` job (the implementer's prompt
   receives them), and for `label-ready` also the job's `if:`, which compares
   `github.event.label.name` with the literal name;
3. nothing for `/plan-issue`: it reads the `label-ready` value from the caller.

Create the renamed labels once (`gh label create <name>`); review creates its verdict labels
if they are missing.

## 2. Prompt extension files

Each stage appends the file named by `extra-instructions-file` (if it exists) under a
`## Project-specific instructions` heading, verbatim: a `{{ x }}` in it (Vue, Handlebars...)
is left as it is. Defaults:

| Stage | File | Put here |
|---|---|---|
| implement, fix-review | `.github/patufet/implement.md` | regression-anchor tests, things never to touch, how to run one test |
| review | `.github/patufet/review.md` | the project review checklist (layers, wrappers, authz rules, ground-truth docs) |
| e2e | `.github/patufet/e2e.md` | the always-check paths of the app |

Keep them short and factual; the agent already reads `CLAUDE.md` / `README`. Never put
instructions there that contradict the base prompt's output contract (markers, structured
result, labels) — the deterministic steps depend on it.

### Placeholders available in base prompts

If you fork and edit `prompts/*.md`: `{{issue}}`, `{{pr}}`, `{{repository}}`, `{{branch}}`,
`{{language}}`, `{{plan}}`, `{{plan_section}}`, `{{ci_section}}`,
`{{cycle}}`, `{{run}}`, `{{review_report}}`, `{{inline_comments}}`, `{{e2e_env}}`,
`{{label_in_progress}}`, `{{label_to_refine}}`, `{{human_reviewer}}`. Each workflow sets the
ones its prompt uses (`tests/run.sh` checks it). Unknown placeholders render empty and are
reported in the job log. The verdict labels have no placeholder: the agents do not label.

## `/plan-issue`

`templates/.claude/commands/plan-issue.md` is a Claude Code slash command copied into the
consumer repository by `bootstrap.sh`. It looks up the facts in the code itself and asks you
only the decisions the issue leaves open, in rounds, each with a recommended answer; a clear
issue gets no questions. It drafts the plan with a `### Decisions` section, so the implementer
does not stop on them, and only on your explicit confirmation posts it (with the
`<!-- patufet:plan -->` marker) and adds the ready label (`ready-to-implement`, or the
`label-ready` of the caller). Run again after `to-refine`, it starts from the implementer's
question. The rounds adapt the method of Matt Pocock's
[`grilling`](https://github.com/mattpocock/skills) skill (MIT).

`bootstrap.sh` does not overwrite an existing copy, so a new version of the command reaches
an adopted repository only when you copy it there.

## Versioning

- `@v1` — moving tag, receives every release. Recommended.
- `@v1.x.y` — pinned; you bump on purpose. The first release with the patufet names is
  `v1.1.0`.
- `@main` — for trying an unreleased change; do not leave consumers on it.

Breaking changes (renamed inputs, new required file, changed markers) are marked
**Breaking** in `CHANGELOG.md` with the migration steps. The release policy, including when
they bump the major, is in [CONTRIBUTING.md](../CONTRIBUTING.md#releasing).
