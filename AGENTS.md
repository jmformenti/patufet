# Adopting patufet — runbook for a coding agent

You are an agent working inside a repository whose owner asked you to adopt patufet, the
issue → PR → review → fix flow described in [README.md](README.md). Follow the steps in
order. Run every command from the root of the consumer repository, not from a clone of
patufet. Steps marked **human** cannot be done by you: report them at the end, do not
work around them.

## 1. Preconditions

Check, and stop with a clear message if any fails:

```bash
git rev-parse --show-toplevel          # inside a git repository
gh auth status                         # gh authenticated
gh repo view --json nameWithOwner      # the repository exists on GitHub
git status --porcelain                 # empty: clean working tree
```

Decide the two bootstrap values before running it:

- `--reviewer`: the GitHub login mentioned when the flow needs a human. Default to
  `gh api user --jq .login` unless the owner told you otherwise.
- `--language`: the language the owner writes issues and PR comments in (ISO code or free
  text). Look at recent issues; default to `en`.
- `--with-e2e`: only if the whole application can start on `ubuntu-latest` from a single
  script (Docker Compose, `npm start`, embedded DB). When in doubt, omit it; it can be added
  later.

## 2. Existing automation

Inventory what is already there before installing; patufet adds workflows, labels and a
branch convention that can collide with them.

```bash
ls .github/workflows/
grep -lE 'anthropics/claude-code-action' .github/workflows/*.y*ml   # other Claude workflows
gh label list --limit 1000 --json name --jq '.[].name'               # existing labels
gh api "repos/{owner}/{repo}/rulesets" --jq '.[].name'               # branch rulesets, if any
```

Then, for each case that applies, do the following and mention it in your final report:

- **A workflow already uses `anthropics/claude-code-action`** (the action's own `@claude`
  or code-review examples). Both would answer the same events: two replies per mention, two
  reviews per push, twice the cost. Ask the owner which to keep. If they keep theirs for
  `@claude` only, delete `.github/workflows/patufet-mention.yml` after the bootstrap; if
  theirs reviews pull requests, it must go, patufet's review job replaces it.
- **One of the flow labels already exists** (`ready-to-implement`, `in-progress`,
  `to-refine`, `blocked`, `pass`, `warning`, `fail`, `needs-human-review`) with another
  meaning, e.g. project boards. The bootstrap leaves existing labels untouched, but the flow
  reacts to those names: a `pass` put on a PR for any other reason starts the e2e stage.
  Rename patufet's through the `label-*` inputs and update the caller's `if:` conditions
  to match; the `/plan-issue` command hard-codes `ready-to-implement`, edit it too. See
  [docs/customization.md](docs/customization.md).
- **Another bot labels pull requests** (`actions/labeler`, release-drafter...). Check that
  none of its labels is a flow label; otherwise rename as above.
- **A ruleset or branch protection restricts branch names or who can push.** The
  implementer pushes `agent/issue-<n>` with the Claude App's token. Change `branch-prefix`
  to an allowed pattern, or the owner must add the App to the bypass list.
- **CI skips pull requests from bots** (`if: github.actor != 'dependabot[bot]'` and the
  like). patufet's PRs are opened by `claude[bot]`; if the tests would not run on them,
  say so in the report and do not describe those jobs in `ci-check-names`.

Files the bootstrap would create that already exist (`.github/patufet/*`,
`.claude/commands/plan-issue.md`) are kept as they are; no action needed.

## 3. Install

```bash
bash <(curl -sSL https://raw.githubusercontent.com/jmformenti/patufet/v1/scripts/bootstrap.sh) \
  --reviewer <login> --language <lang> [--with-e2e]
```

It is idempotent and never overwrites an existing file. It copies the caller workflows,
the prompt extension files and the `/plan-issue` command, creates the eight flow labels and
checks for the secret. Read its output: the final "Next steps" block and any `WARNING`.

## 4. Fill in what the bootstrap cannot infer

`.github/workflows/patufet.yml` (the caller):

- `test-command` appears **twice** (`implement` and `fix-review` jobs) and must be the same
  in both. Replace the `TODO` with the shell that runs the project's tests and build, as CI
  runs them (`package.json` scripts, `Makefile`, `pom.xml`, existing workflows under
  `.github/workflows/`). Multi-line is fine. Leave it empty only if there is no way to
  test the project.
- `ci-check-names` (`review` job): a short human description of the CI jobs that already
  test the PR, e.g. `"CI / test (unit + build)"`. It is prose, not job IDs. Leave `""` if
  the repository has no CI on pull requests.
- Keep `language` and `human-reviewer` as the bootstrap set them.

`.github/patufet/implement.md` and `.github/patufet/review.md`: project knowledge the
agents will not find in `CLAUDE.md` or the README. Write short bullet lists, derived from
the repository, only for things that are true and specific:

- `implement.md`: the regression-anchor tests, how to run a single test, what must never
  be touched.
- `review.md`: the review checklist (layering rules, mandatory wrappers, authorization
  rules, ground-truth documents).

If you have nothing factual to add, delete the file. Never write instructions that change
the agents' output contract (markers, labels, structured result).

With `--with-e2e` only: adapt `.github/patufet/e2e-up.sh` so it starts the app, waits
until it answers, seeds test data and appends `KEY=VALUE` lines to `$PATUFET_E2E_ENV`
(URL and throwaway credentials). `e2e-down.sh` must stop everything and never fail.
Describe in `.github/patufet/e2e.md` what must always be exercised. Full contract:
[docs/e2e.md](docs/e2e.md).

## 5. Verify

```bash
grep -n TODO .github/workflows/patufet.yml                 # must print nothing
gh label list --json name --jq '.[].name' | sort            # must include the 8 flow labels:
# blocked fail in-progress needs-human-review pass ready-to-implement to-refine warning
gh secret list --json name --jq '.[].name'                  # CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY
actionlint .github/workflows/patufet*.yml                   # if actionlint is installed
bash -n .github/patufet/*.sh                                # with --with-e2e
```

A missing secret is a **human** step (section 7), not a failure of yours.

## 6. Commit

Follow the repository's conventions (direct commit or PR). The workflows only become active
once the files are on the default branch.

Expected: **the PR that adds `patufet.yml` gets no automatic review.** The Claude action
refuses to run from a workflow file that differs from the default branch's copy and fails
the `review` job with an explicit validation error. This is normal; merge that PR by hand
after the usual CI is green. Every later PR is reviewed. The same happens on any future PR
that edits `patufet.yml`.

## 7. Hand over to the human

Report these, done or pending, with the exact commands:

1. **Install the Claude GitHub App** on the repository: https://github.com/apps/claude
2. **Set the secret**, if `gh secret list` did not show one:
   `claude setup-token` locally, then `gh secret set CLAUDE_CODE_OAUTH_TOKEN` (or
   `gh secret set ANTHROPIC_API_KEY`). Each repository must use its owner's own
   credentials; see [docs/security.md](docs/security.md).
3. **Read the cost and safety notes** in the README before enabling this on a public
   repository. Runs are billed to that key.
4. **Start the first cycle** on a small issue: `/plan-issue <n>` from Claude Code, approve
   the plan. The `ready-to-implement` label starts the implementer immediately, so only the
   human adds it.

## Reference

- Every input of the reusable workflows: [docs/customization.md](docs/customization.md)
- Labels, markers, concurrency: [docs/architecture.md](docs/architecture.md)
- Known failure modes: [docs/troubleshooting.md](docs/troubleshooting.md)
- Pin a version by replacing `@v1` with `@v1.x.y` in both caller workflows; changes are in
  [CHANGELOG.md](CHANGELOG.md).
