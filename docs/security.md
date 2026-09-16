# Security model

The implementer and fix-review agents run with `contents: write` and `pull-requests: write`
on your repository, and they act on natural-language instructions. The whole design question
is therefore: **whose text can reach an agent that has write access?**

## Who can start a run

| Stage | Trigger | Who can cause it |
|---|---|---|
| implement | label `ready-to-implement` | only users who can label issues (triage/write) |
| review | PR opened / pushed | anyone with a PR — but review has **read-only** repo access; its outputs are comments and labels |
| fix-review | label `warning` / `fail` | the automation (App token) or a collaborator |
| e2e | label `pass` | same |
| mention | `@claude` in a comment | the action only answers users with write access (`allowed_non_write_users` is never set) |

`allowed_bots` is set to `claude` only, so the events created by the automation itself can
chain, but no other GitHub App can drive the flow.

Pull requests from forks never receive secrets, so they cannot run the Claude action at all.

## What text an agent reads

| Agent | Input it acts on | Trust filter |
|---|---|---|
| implement | the plan | latest issue comment with `<!-- patufet:plan -->` whose author is `OWNER` / `MEMBER` / `COLLABORATOR` (`scripts/find-plan.sh`). A plan comment by anyone else is ignored and the run is blocked. |
| fix-review | the review report + inline comments | pre-fetched by the workflow from trusted authors only (collaborators, `claude[bot]`, `github-actions[bot]`); the prompt tells the agent to ignore any other source |
| review, e2e | the PR diff, the issue and plan | read-only on code (`contents: read`); may edit PR labels/comments; plan filtered as above |
| mention | the comment | gated by the action's write-permission check |

Untrusted text still reaches the agents: the **PR diff** itself (review, e2e) and the **issue
body** (only through the plan you write, which you control). On a public repository, assume
that a stranger can plant instructions in an issue body; the plan gate means you have read
it before anything with write access runs.

## Tokens

- `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY`: repository secrets, passed with
  `secrets: inherit`. They never leave the consumer repository; this template holds none.
- Each consumer must use **its own** credentials, billed to their owner. An OAuth token is
  tied to one person's Claude subscription and is meant for that person's ordinary use of
  Claude Code (its official action accepts it for that person's repositories); never share
  one across people or organisations, and use an API key for anything that is not your own
  usage. See Anthropic's [legal and compliance](https://code.claude.com/docs/en/legal-and-compliance) page.
- Checkout uses `persist-credentials: false`; pushes go through `gh auth setup-git` with the
  job's `GITHUB_TOKEN`, and the action's own App token for its GitHub operations.
- `show-full-output: true` prints the whole transcript, including tool outputs. Anything a
  test prints (a dev secret, a token) ends up in the log. Set it to `false` on public
  repositories once the flow is stable, or make sure nothing sensitive is printed.

## Permissions per job

Declared in each reusable workflow and required in the caller (the caller cannot grant less):

| Workflow | contents | pull-requests | issues | id-token | actions |
|---|---|---|---|---|---|
| implement | write | write | write | write | – |
| fix-review | write | write | read | write | – |
| review | read | write | read | write | – |
| e2e | read | write | read | write | – |
| mention | read | read | read | write | read |

## Residual risks, honestly

- A collaborator account compromise gives full control of the flow (as of any CI).
- `max-turns` is the only cap: a misbehaving run can spend the whole budget of turns.
- The e2e hook runs arbitrary shell from the PR branch on the runner — same trust level as
  any CI job on that branch.
