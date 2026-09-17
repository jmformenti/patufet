# patufet

Reusable GitHub Actions workflows that turn a GitHub issue into a merged-ready pull request
with [Claude Code](https://code.claude.com), keeping a human in the loop at the two points
that matter: **approving the plan** and **merging**.

```mermaid
flowchart LR
    issue([issue]) -->|"/plan-issue"| plan[plan approved]
    plan -->|label| implement
    implement --> pr[PR]
    pr --> review
    review -->|"warning / fail"| fix[fix-review]
    fix -->|push| pr
    review -->|pass| e2e["e2e (optional)"]
    e2e -->|✅| human[human review + merge]
```

Everything runs on `anthropics/claude-code-action`; this repository adds the **state machine**
(labels), the **review → fix loop** with a cycle limit, the **plan gate**, an optional **live
e2e stage** with Playwright, and the guards that make it safe and cheap enough to leave
unattended. Consumer repositories hold ~80 lines of YAML and a few Markdown files.

## Quick start

Requirements: a GitHub repository, the [Claude GitHub App](https://github.com/apps/claude)
installed on it, a `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`) or `ANTHROPIC_API_KEY`
secret, and the `gh` CLI locally.

```bash
cd your-repo
bash <(curl -sSL https://raw.githubusercontent.com/jmformenti/patufet/main/scripts/bootstrap.sh) \
  --reviewer your-github-login --language en          # add --with-e2e if the app can run on a runner
```

Then:

1. Fill in `test-command` (and `ci-check-names`) in `.github/workflows/patufet.yml`.
2. Optionally write your project checklist in `.github/patufet/review.md` / `implement.md`.
3. Commit and push.
4. Open an issue, run `/plan-issue <n>` from Claude Code, approve the plan → the flow starts.

Want a coding agent to do the adoption for you? Point it at
[AGENTS.md](AGENTS.md), the same steps written as a runbook, with the parts only a human can
do (App install, secret, first plan) called out:

```
Adopt patufet in this repository: read
https://raw.githubusercontent.com/jmformenti/patufet/v1/AGENTS.md and follow it.
```

## How a cycle goes

| Step | Trigger | Who | Result |
|---|---|---|---|
| Plan | you, `/plan-issue N` locally | Claude Code + you | comment `<!-- patufet:plan -->` + label `ready-to-implement` |
| Implement | label `ready-to-implement` | `implement.yml` | branch `agent/issue-N`, tests green, PR with `Closes #N` — or draft PR + `to-refine` when it has a question |
| Review | PR opened / pushed / ready | `review.yml` | inline comments, one report comment, label `pass` / `warning` / `fail` |
| Fix | label `warning` / `fail` | `fix-review.yml` | fixes pushed to the PR branch → review again (max `max-review-cycles`, then `needs-human-review`) |
| E2E | label `pass` | `e2e.yml` (optional) | app started by your `e2e-up.sh`, tested live with Playwright; `fail` sends it back, success mentions the reviewer |
| Merge | you | — | — |

The full state machine, markers and concurrency rules: [docs/architecture.md](docs/architecture.md).

## Configuration

Every knob is an input of the reusable workflows (language, model, `max-turns`, allowed tools,
label names, test command, cycle limit, hook paths...). Project-specific knowledge goes in
Markdown files appended to the base prompts. See [docs/customization.md](docs/customization.md).

## Cost and safety — read before enabling

- **Runs are billed against your Claude subscription/API key.** One issue typically costs one
  implement run, one review run per push, plus fix runs. Defaults follow real usage on
  habitus-trainer (`max-review-cycles: 10`, `max-turns` 200–400). See the cost section in
  [docs/architecture.md](docs/architecture.md#cost).
- **The agent has write access to your repository.** Only collaborators can start it (labels),
  and it only reads plans and review reports written by collaborators or the automation bots.
  Read [docs/security.md](docs/security.md) for the threat model before using this on a public
  repository.
- **Workflows cannot be tested locally.** Adopt on a small issue first, then pin the version.
  See [docs/troubleshooting.md](docs/troubleshooting.md) for the failure modes already met.

## Repository layout

```
.github/workflows/   reusable workflows (workflow_call): implement, review, fix-review, e2e, mention
prompts/             base prompts (English), rendered with {{placeholders}} + your extension files
scripts/             helpers used by the workflows, and bootstrap.sh
templates/           files copied into consumer repositories
docs/                architecture, customization, e2e, security, troubleshooting, migration
AGENTS.md            adoption runbook for coding agents
```

Versioning: consumers reference `@v1` (moving major tag) or an exact `@v1.x.y`. Changes are
listed in [CHANGELOG.md](CHANGELOG.md).

## Trademarks

patufet is an independent open-source project. It runs [Claude Code](https://code.claude.com)
through Anthropic's `claude-code-action`, but it is not built, endorsed or sponsored by
Anthropic. "Claude" and "Claude Code" are trademarks of Anthropic, PBC, used here only to
describe compatibility.

## License

MIT — see [LICENSE](LICENSE).
