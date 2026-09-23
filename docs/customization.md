# Customization

Three layers, from cheapest to deepest:

1. **Inputs** of the caller workflow (`with:`) — language, commands, limits, labels, model.
2. **Prompt extension files** in the consumer repository — project knowledge appended to the
   base prompts.
3. **Forking** this repository — only if you need to change the base prompts or the flow.
   `job.workflow_repository` makes a fork self-contained: callers just point `uses:` at it.

## 1. Inputs

Every input also has a `description:` in its workflow, shown by GitHub when editing the
caller.

Common to `implement`, `review`, `fix-review`, `e2e`:

| Input | Default | Notes |
|---|---|---|
| `language` | `en` | Language of the comments / PR descriptions Claude writes. Free text or ISO code. Code and commit messages follow the repository conventions, not this. |
| `model` | *(action default)* | Passed as `--model`. A cheaper model for `review` is a common saving. |
| `max-turns` | 400 (implement, review, fix-review) / 200 (e2e) | Hard cap on agent turns. |
| `allowed-tools` | per workflow | `--allowedTools`. Implementer and fixer get `Bash,Edit,Write,Read,Glob,Grep`; reviewer and e2e tester only `gh pr view/diff/comment/edit`, `gh issue view` and their read / MCP tools. Inside the action `gh` uses the Claude App token, which **can write**: widen these two only knowing that (see [security.md](security.md)). |
| `claude-args-extra` | `''` | Anything else for `claude_args`. |
| `show-full-output` | `true` | Full transcript in the job log. Needed to diagnose tool denials; may echo secrets printed by tools. |
| `extra-instructions-file` | `.github/patufet/<stage>.md` | See layer 2. |
| `timeout-minutes` | 45 (implement, fix-review) / 30 (review, e2e) | Job timeout. |

`implement`:

| Input | Default | Notes |
|---|---|---|
| `issue-number` | *(required)* | The caller passes `fromJSON(inputs.issue \|\| github.event.issue.number)`. |
| `branch-prefix` | `agent/issue-` | Branch = prefix + issue number. Also used by review/e2e to find the linked issue. |
| `test-command` | `''` | Multi-line shell that must pass before a PR is opened. Empty = the agent infers it from the repo docs (less reliable). The template writes it once and reuses it in `fix-review` with a YAML alias. |
| `legacy-plan-heading` | `''` | Also accept plan comments that *contain* this heading (e.g. `## Pla d'implementació`) — migration aid, remove once old issues are done. Also on `review` and `e2e`. |
| `label-ready`, `label-in-progress`, `label-to-refine`, `label-blocked` | `ready-to-implement`, `in-progress`, `to-refine`, `blocked` | See [Renaming the labels](#renaming-the-labels). |

`review`:

| Input | Default | Notes |
|---|---|---|
| `ci-check-names` | `''` | Human description of the CI jobs that already run tests/build on PRs, so the reviewer does not attempt to (it cannot) and knows where to look. |
| `branch-prefix` | `agent/issue-` | Same as implement, to find the linked issue. |
| `allowed-bots` | `claude` | The implementer opens PRs as the `claude` bot; without this the action refuses bot-triggered events. Also on `fix-review` and `e2e`. |
| `label-pass`, `label-warning`, `label-fail`, `label-needs-human-review` | `pass`, `warning`, `fail`, `needs-human-review` | Created if missing (existing labels are never modified). |

Output: `verdict` (`pass` / `warning` / `fail`).

`fix-review`:

| Input | Default | Notes |
|---|---|---|
| `max-review-cycles` | `10` | Reports before handing over to a human. |
| `human-reviewer` | `''` | Login (no `@`) mentioned when the limit is reached. |
| `test-command` | `''` | Same as implement. |
| `label-needs-human-review` | `needs-human-review` | Set when the limit is reached. |

`e2e`: see [e2e.md](e2e.md) (`label-pass`, `label-warning`, `label-fail` as in review).

`mention`: `model`, `claude-args-extra`, `timeout-minutes`.

### Renaming the labels

Rename when a flow label already means something else in the repository (a project board's
`blocked`, a bot's `pass`...). Three places, all in the consumer repository:

1. the `label-*` inputs of every job that has them (the prompts receive the names, so Claude
   labels with yours);
2. the caller's `if:` conditions, which compare `github.event.label.name` with literal names;
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
`{{language}}`, `{{plan}}`, `{{plan_section}}`, `{{test_command}}`, `{{ci_section}}`,
`{{cycle}}`, `{{run}}`, `{{review_report}}`, `{{inline_comments}}`, `{{e2e_env}}`,
`{{label_in_progress}}`, `{{label_to_refine}}`, `{{label_pass}}`, `{{label_warning}}`,
`{{label_fail}}`, `{{label_needs_human_review}}`. Each workflow sets the ones its prompt
uses (`tests/run.sh` checks it). Unknown placeholders render empty and are reported in the
job log.

## `/plan-issue`

`templates/.claude/commands/plan-issue.md` is a Claude Code slash command copied into the
consumer repository by `bootstrap.sh`. It drafts the plan with you, and only on your explicit
confirmation posts it (with the `<!-- patufet:plan -->` marker) and adds the ready label
(`ready-to-implement`, or the `label-ready` of the caller).

Future option: distribute the command as a Claude Code plugin from this repository instead
of a copied file.

## Versioning

- `@v1` — moving tag, receives every release. Recommended.
- `@v1.x.y` — pinned; you bump on purpose. The first release with the patufet names is
  `v1.1.0`.
- `@main` — for trying an unreleased change; do not leave consumers on it.

Breaking changes (renamed inputs, new required file, changed markers) are marked
**Breaking** in `CHANGELOG.md` with the migration steps. The release policy, including when
they bump the major, is in [CONTRIBUTING.md](../CONTRIBUTING.md#releasing).
