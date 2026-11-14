# Adopting patufet

## In a new repository

Follow the README (with an agent: [ADOPTING.md](../ADOPTING.md)). Then open a small issue (a
text change, a test) and run one full cycle before trusting it with real work.

## Upgrading

- On `@v1`: nothing to do for compatible releases; read `CHANGELOG.md` for new inputs.
- Major bump: the changelog lists the renamed inputs / new files; update the caller and the
  extension files, then change `@v1` → `@v2`.

### To v1.7.0

Compatible and optional: a caller with the `review`, `fix-review`, `e2e` and `fix-e2e` jobs keeps
working, since those workflows stay. To move to the single `pull-request` job, in
`.github/workflows/patufet.yml`:

1. Replace those four jobs with the `pull-request` job of
   [the template](../templates/.github/workflows/patufet.yml). Keep `implement` as it is.
2. Copy your values into its `with:`. `language`, `model`, `human-reviewer`, `max-review-cycles`,
   `java-version`, `node-version` and the `label-*` keep their names and are set once. `max-turns`,
   `allowed-tools`, `timeout-minutes` and `extra-instructions-file` take the stage as a prefix
   (`review-`, `fix-`, `e2e-`), and the e2e hooks are `e2e-up-script` / `e2e-down-script`
   ([customization.md](customization.md#pull-request)).
3. Set `e2e: true` if you had the `e2e` job, `e2e: false` otherwise.
4. Check the permissions of the job: `contents: write`, `pull-requests: write`, `issues: read`,
   `id-token: write`, `actions: read`. With fewer the run does not start.
5. If a branch protection rule requires the checks by name, they are now
   `pull-request / review / review` and `pull-request / e2e / e2e`.

Like every PR that edits `patufet.yml`, this one gets no automatic review: merge it by hand.

### To v1.6.0

**Breaking:** the `ci-checks` input no longer exists. A caller that still passes it fails at once
with `Invalid input, ci-checks is not defined in the referenced workflow`, and no stage runs. In
`.github/workflows/patufet.yml`, `review` job: remove `ci-checks` and the comment above it, as in
the step 1 of v1.5.0 below. A caller that already did that for v1.5.0 has nothing to do.

### To v1.5.0

Compatible: nothing breaks, but `ci-checks` is now ignored, with a warning in the review's log. The
review waits for every workflow that runs on the PR's commit (decision 12). In
`.github/workflows/patufet.yml`:

1. `review` job: remove `ci-checks` and the comment above it. If it listed only some of the jobs of
   your workflows on pull requests, check that the others may be waited for too, since a red one
   is now a `fail`.
2. `review` job: keep `actions: read`. You can remove `checks: read`, which is no longer used.
3. If your CI runs outside GitHub Actions, the review no longer waits for it. See
   [The CI-aware review](customization.md#the-ci-aware-review).

As with any PR that edits the caller, this one gets no automatic review.

### To v1.4.0 (breaking)

The stages after a review now run in the review's own run, chained with `needs:`, and Claude no
longer labels (decision 11). With an old caller, **the flow stops after every review**: the
workflow sets the verdict label with `GITHUB_TOKEN`, which starts nothing. The new caller also
works with v1.3.x, so migrate it first and then let `@v1` move. In
`.github/workflows/patufet.yml`, compared with `templates/.github/workflows/patufet.yml`:

1. `fix-review` job: add `needs: review` and replace its `if:` with the template's, which runs it
   on `needs.review.outputs.next-stage == 'fix-review'` or on a `warning` / `fail` label that a
   person adds. Keep the `!cancelled()`: without it the job is skipped whenever the review is,
   which is the case on every `labeled` event.
2. `e2e` job, if you have one: the same with `next-stage == 'e2e'` and the `pass` label.
3. Also if you have `e2e`: add the `fix-e2e` job after it (`needs: e2e`). It has the same `with:`
   as `fix-review`.
4. If you renamed the verdict labels, keep your names in the new `if:` conditions.
5. If you widened `allowed-tools` of `review` or `e2e` with `Bash(gh pr edit:*)` for the labels,
   remove it: the agents no longer label.

As with any PR that edits the caller, this one gets no automatic review.

### From v1.3.x or older

Do not migrate step by step: the callers of those versions pass inputs that no longer exist
(`test-command`, `ci-check-names`, `legacy-plan-heading`, `ci-checks`), and such a caller is an
invalid workflow. Replace it instead:

1. Without CI on pull requests, add a CI workflow first: the review waits for it, and the agents
   reproduce it.
2. Replace `.github/workflows/patufet.yml` and `patufet-mention.yml` with the ones in
   `templates/.github/workflows/`, and carry over your `with:` values that still exist (see
   [customization.md](customization.md)). Remove the `e2e` and `fix-e2e` jobs if you have no e2e
   stage.
3. Add the line `<!-- patufet:plan -->` to the plans of open issues that do not have it.
4. Check that `AGENTS.md` / `CLAUDE.md` describe the build and test commands correctly.

As with any PR that edits the caller, this one gets no automatic review.
