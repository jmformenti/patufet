# Security model

The implementer and fix-review agents run with `contents: write` and `pull-requests: write`
on your repository, and they act on natural-language instructions. The whole design question
is therefore: **whose text can reach an agent that has write access?**

## Who can start a run

| Stage | Trigger | Who can cause it |
|---|---|---|
| implement | label `ready-to-implement` | only users who can label issues (triage/write) |
| review | PR opened / pushed | anyone who can push a branch (fork PRs get no secrets); its tools only read and comment: no labels, no merge, no push (see [Tokens](#tokens)) |
| fix-review | a `warning` / `fail` verdict of the review in the same run (`needs:`), or a person adding that label | the workflow's deterministic verdict step, or a collaborator |
| e2e | a `pass` verdict of the review in the same run, or a person adding `pass` | same |
| mention | `@claude` in a comment | the action only answers users with write access (`allowed_non_write_users` is never set) |

`allowed_bots` is set to `claude` only, so the PRs and pushes of the automation itself can start
a review, but no other GitHub App can drive the flow. Labels never start a stage when the
automation sets them: the workflow sets them with `GITHUB_TOKEN`, whose events start nothing
(decision 11).

Pull requests from forks never receive secrets, so they cannot run the Claude action at all.

## What text an agent reads

| Agent | Input it acts on | Trust filter |
|---|---|---|
| implement | the plan | latest issue comment with `<!-- patufet:plan -->` whose author is `OWNER` / `MEMBER` / `COLLABORATOR` (`scripts/find-plan.sh`). A plan comment by anyone else is ignored and the run is blocked. |
| fix-review | the latest review or e2e report + inline comments | pre-fetched by the workflow from trusted authors only (collaborators, `claude[bot]`, `github-actions[bot]`); the prompt tells the agent to ignore any other source |
| review, e2e | the PR diff, the issue and plan (review also the end of the failed CI logs; e2e also the pages of the running app) | checkout with `contents: read`; tools limited to `gh pr view/diff/comment` and `gh issue view` (no `gh pr edit`, no `gh api`, no `gh pr merge`); the verdict is a structured result that a deterministic step turns into a label; plan filtered as above |
| mention | the comment | gated by the action's write-permission check |

Untrusted text still reaches the agents: the **PR diff** itself (review, e2e), the **failed CI
logs** (review; the code under review prints them, so they are no more trusted than the diff, and
GitHub masks the secrets it knows in them) and the **issue body** (only through the plan you
write, which you control). The reviewer's report then reaches `fix-review`, as it always has,
and so does the e2e tester's report after a failed live test, which was written after reading pages
rendered by the PR's code.
On a public repository, assume that a stranger can plant instructions in an issue body; the plan gate means you have read
it before anything with write access runs.

## Tokens

- `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY`: repository secrets. The caller passes only
  these two, not `secrets: inherit`: the workflows are referenced by the movable `@v1` tag, so they
  should not get the rest of the repository's secrets. They are stored only in the consumer
  repository, not in this template or in patufet, and reach the runner when a job runs.
- Each consumer must use **its own** credentials, billed to their owner. An OAuth token is
  tied to one person's Claude subscription and is meant for that person's ordinary use of
  Claude Code (its official action accepts it for that person's repositories); never share
  one across people or organisations, and use an API key for anything that is not your own
  usage. See Anthropic's [legal and compliance](https://code.claude.com/docs/en/legal-and-compliance) page.
- Checkout uses `persist-credentials: false`; pushes go through `gh auth setup-git`.
- In `e2e`, the job's `GITHUB_TOKEN` is set only on the steps that call `gh`. The hooks and the
  application they start are code of the PR and do not get it.
- **Inside the action, `gh` and git use the Claude App token**, not the job's
  `GITHUB_TOKEN`. The action requests it with `contents`, `pull_requests` and `issues`
  **write** whatever the job's `permissions:` say (claude-code-action `src/github/token.ts`),
  so the job permissions do not limit what an agent can do through `gh`. What limits it is
  `allowed-tools`: the reviewer and the e2e tester — the agents that read untrusted content
  (the diff, the running app) — only get the `gh` subcommands they need to read and
  comment. They do not label: they return a structured verdict and a deterministic step sets
  the label, so a prompt injection in the diff or the app can post comments, but not edit the
  PR, merge, push or call the API. Widening their
  `allowed-tools` (e.g. `Bash(gh api:*)`, `Bash(gh pr *)`) gives them write access to the
  repository, including merging the PR.
- `show-full-output: true` prints the whole transcript, including tool outputs. Anything a
  test prints (a dev secret, a token) ends up in the log. Set it to `false` on public
  repositories once the flow is stable, or make sure nothing sensitive is printed.

## Permissions per job

Declared in each reusable workflow and required in the caller (the caller cannot grant less),
except on `review`, which declares none and takes those of the caller's job: its `actions: read`
is opt-in, and a declared list could not leave it optional
([decision 10](decisions.md#10-the-repositorys-ci-is-the-source-of-truth-the-review-waits-for-it-in-pull_request)).
So on that job the caller's list is the only limit: always declare it.

They bound the steps that use `GITHUB_TOKEN`, not the agents (see [Tokens](#tokens)):

| Workflow | contents | pull-requests | issues | id-token | actions |
|---|---|---|---|---|---|
| implement | write | write | write | write | – |
| fix-review | write | write | read | write | – |
| review | read | write | read | write | read |
| e2e | read | write | read | write | – |
| mention | read | read | read | write | read |

The caller's `pull-request` job grants the most a stage needs (`contents: write`,
`pull-requests: write`, `issues: read`, `id-token: write`, `actions: read`), and
`pull-request.yml` gives each of its jobs the row above: `review` and `e2e`, which check out and
run the code of the PR, keep `contents: read`.

## Residual risks, honestly

- A collaborator account compromise gives full control of the flow (as of any CI).
- `max-turns` is the only cap: a misbehaving run can spend the whole budget of turns.
- The e2e hook runs arbitrary shell from the PR branch on the runner — same trust level as
  any CI job on that branch.
- `actions/checkout` and `anthropics/claude-code-action` are referenced by major tag, like
  consumers reference patufet; a compromised tag would reach every run. Tools fetched at run
  time (`@playwright/mcp`, the Playwright browser, actionlint in self-check) are pinned to
  exact versions. See [decisions.md](decisions.md#9-third-party-actions-pinned-by-major-tag-tools-by-exact-version).
