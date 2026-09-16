# Customization

Three layers, from cheapest to deepest:

1. **Inputs** of the caller workflow (`with:`) — language, commands, limits, labels, model.
2. **Prompt extension files** in the consumer repository — project knowledge appended to the
   base prompts.
3. **Forking** this repository — only if you need to change the base prompts or the flow.
   `job.workflow_repository` makes a fork self-contained: callers just point `uses:` at it.

## 1. Inputs

Common to `implement`, `review`, `fix-review`, `e2e`:

| Input | Default | Notes |
|---|---|---|
| `language` | `en` | Language of the comments / PR descriptions Claude writes. Free text or ISO code. Code and commit messages follow the repository conventions, not this. |
| `model` | *(action default)* | Passed as `--model`. A cheaper model for `review` is a common saving. |
| `max-turns` | 200 (implement, fix-review) / 100 (review, e2e) | Hard cap on agent turns. |
| `allowed-tools` | per workflow | `--allowedTools`. Implementers need `Bash`; reviewers get a read-only set plus the inline-comment MCP tool. |
| `claude-args-extra` | `''` | Anything else for `claude_args`. |
| `show-full-output` | `true` | Full transcript in the job log. Needed to diagnose tool denials; may echo secrets printed by tools. |
| `extra-instructions-file` | `.github/patufet/<stage>.md` | See layer 2. |
| `label-*` | `ready-to-implement`, `in-progress`, `to-refine`, `blocked`, `pass`, `warning`, `fail`, `needs-human-review` | Rename freely; keep the caller's `if:` conditions in sync. |
| `legacy-plan-heading` | `''` | Also accept plan comments that *contain* this heading (e.g. `## Pla d'implementació`) — migration aid, remove once old issues are done. |
| `timeout-minutes` | 45 / 30 | Job timeout. |

`implement`:

| Input | Default | Notes |
|---|---|---|
| `issue-number` | *(required)* | The caller passes `fromJSON(inputs.issue \|\| github.event.issue.number)`. |
| `branch-prefix` | `agent/issue-` | Branch = prefix + issue number. Also used by review/e2e to find the linked issue. |
| `test-command` | `''` | Multi-line shell that must pass before a PR is opened. Empty = the agent infers it from the repo docs (less reliable). |

`review`:

| Input | Default | Notes |
|---|---|---|
| `ci-check-names` | `''` | Human description of the CI jobs that already run tests/build on PRs, so the reviewer does not attempt to (it cannot) and knows where to look. |
| `allowed-bots` | `claude` | The implementer opens PRs as the `claude` bot; without this the action refuses bot-triggered events. |

`fix-review`:

| Input | Default | Notes |
|---|---|---|
| `max-review-cycles` | `3` | Reports before handing over to a human. |
| `human-reviewer` | `''` | Login (no `@`) mentioned when the limit is reached. |
| `test-command` | `''` | Same as implement. |

`e2e`: see [e2e.md](e2e.md).

`mention`: `model`, `claude-args-extra`, `timeout-minutes`.

## 2. Prompt extension files

Each stage appends the file named by `extra-instructions-file` (if it exists) under a
`## Project-specific instructions` heading. Defaults:

| Stage | File | Put here |
|---|---|---|
| implement, fix-review | `.github/patufet/implement.md` | regression-anchor tests, things never to touch, how to run one test |
| review | `.github/patufet/review.md` | the project review checklist (layers, wrappers, authz rules, ground-truth docs) |
| e2e | `.github/patufet/e2e.md` | the always-check paths of the app |

Keep them short and factual; the agent already reads `CLAUDE.md` / `README`. Never put
instructions there that contradict the base prompt's output contract (markers, structured
result, "do not label") — the deterministic steps depend on it.

### Placeholders available in base prompts

If you fork and edit `prompts/*.md`: `{{issue}}`, `{{pr}}`, `{{repository}}`, `{{branch}}`,
`{{language}}`, `{{plan}}`, `{{plan_section}}`, `{{test_command}}`, `{{ci_section}}`,
`{{cycle}}`, `{{review_report}}`, `{{inline_comments}}`, `{{e2e_env}}`,
`{{label_in_progress}}`, `{{label_to_refine}}`. Unknown placeholders render empty and are
reported in the job log.

## `/plan-issue`

`templates/.claude/commands/plan-issue.md` is a Claude Code slash command copied into the
consumer repository by `bootstrap.sh`. It drafts the plan with you, and only on your explicit
confirmation posts it (with the `<!-- patufet:plan -->` marker) and adds the
`ready-to-implement` label. If you renamed that label, edit the copied command.

Future option: distribute the command as a Claude Code plugin from this repository instead
of a copied file. Not done in v1 to keep the surface small.

## Versioning

- `@v1` — moving tag, receives every compatible fix. Recommended.
- `@v1.x.y` — pinned; you bump on purpose.
- `@main` — for trying an unreleased change; do not leave consumers on it.

Breaking changes (renamed inputs, new required file, changed markers) bump the major and are
listed in `CHANGELOG.md` with the migration steps.
