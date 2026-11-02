Implement issue #{{issue}} of the repository `{{repository}}` following **exactly** the
approved plan reproduced below. Do not re-plan: the plan was reviewed and accepted by a human.

<plan>
{{plan}}
</plan>

Write every comment, PR title and PR description in this language: **{{language}}**. Code,
identifiers and commit messages follow the repository's own conventions (see CLAUDE.md,
CONTRIBUTING or README if present; default to English and Conventional Commits).

## Branch and commits

- Work on the branch `{{branch}}`. If it already exists, inspect what it contains and continue
  from there when it is consistent with the plan; otherwise recreate it from the default branch.
- Commit and push every time you complete a coherent part of the plan (e.g. the backend
  changes, the translations, each group of components). If the run is interrupted, the work is
  not lost and a later run can resume from the branch.

## Verification before opening a PR

Run the relevant tests and build before opening any PR: reproduce locally the steps of the CI workflows in
`.github/workflows/` that run on pull requests; if there are none, run what AGENTS.md, CLAUDE.md
or README document as the tests and build. If a step cannot run on this runner (a missing tool or
service), say so in the PR: CI checks the PR again. If no workflow runs on pull requests, nothing
else will check it, so treat it as an open question.

Never open a PR with failing tests. If a test fails and you cannot fix it with the information
available, treat it as an open question (see below).

## If you can complete the implementation with green tests

- Commit and push to `{{branch}}`.
- Check whether a PR from that branch against the default branch already exists
  (`gh pr list --head {{branch}} --state open`). It may be a draft from an earlier cycle that
  ended in `{{label_to_refine}}`. If it exists, update its description and take it out of draft
  mode with `gh pr ready`; otherwise open a new one. In both cases the final description must
  include `Closes #{{issue}}`.

## If an open question arises that the available information cannot resolve

(ambiguity in the plan, a design decision it does not cover, a failing test you cannot fix...)

- Push everything you have so far to `{{branch}}`, even if unfinished.
- Open (or update) a **draft** PR against the default branch summarising how far you got.
- Leave a clear comment on issue #{{issue}} explaining the concrete question.
- Change the issue label from `{{label_in_progress}}` to `{{label_to_refine}}`.
- Stop: do not keep trying to complete the rest of the implementation.

Never leave a silent partial commit: either the work is clean with a PR open (final or draft),
or the issue is marked `{{label_to_refine}}` with the reason explained.
