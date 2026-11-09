# Adopting patufet

## In a new repository

Follow the README (with an agent: [ADOPTING.md](../ADOPTING.md)). Then open a small issue (a
text change, a test) and run one full cycle before trusting it with real work.

## In a repository that already has a copied version of the flow

This is the path the original project (`habitus-trainer`) followed.

1. Run the bootstrap; it never overwrites, so remove the old workflows first or copy the
   new caller by hand:
   - delete `claude-implementer.yml`, `claude-code-reviewer.yml`, `claude-e2e-tester.yml`,
     `claude.yml`;
   - add `templates/.github/workflows/patufet.yml` and `patufet-mention.yml`.
2. Move the project-specific parts of the old prompts into the extension files:
   - review checklist → `.github/patufet/review.md`;
   - implementer hints → `.github/patufet/implement.md`;
   - the e2e readiness/seeding shell → `.github/patufet/e2e-up.sh` / `e2e-down.sh`, and
     what to always test → `.github/patufet/e2e.md`.
3. Set `human-reviewer` and `language` in the caller.
4. Open issues whose plan comment has no marker: edit the comment and prepend the line
   `<!-- patufet:plan -->`.
5. Update the local `/plan-issue` command (`.claude/commands/plan-issue.md`) so it writes the
   `<!-- patufet:plan -->` marker.
6. Clean up: repository variables the old flow used (e.g. `MAX_REVIEW_CYCLES` → input
   `max-review-cycles`), dead labels, `README` section pointing here.
7. First run on `@main` while iterating on the template if needed, then switch to `@v1`.

## Upgrading

- On `@v1`: nothing to do for compatible releases; read `CHANGELOG.md` for new inputs.
- Major bump: the changelog lists the renamed inputs / new files; update the caller and the
  extension files, then change `@v1` → `@v2`.

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

### To v1.3.0 (breaking)

The `test-command`, `ci-check-names` and `legacy-plan-heading` inputs no longer exist: **a caller
that still passes one is an invalid workflow, and its flow stops**. Do this before `@v1` reaches
that repository, or pin it to `@v1.2.0` until then. In `.github/workflows/patufet.yml`:

1. Without CI on pull requests, add a CI workflow first, running what `test-command` ran.
2. `review` job: add `ci-checks: "<check names>"` and `human-reviewer: "<login>"`, remove
   `ci-check-names`, and add `actions: read` and `checks: read` to `permissions`. See
   [The CI-aware review](customization.md#the-ci-aware-review) for the names to use.
3. `implement` and `fix-review` jobs: remove `test-command`. Add `java-version` / `node-version`
   instead of any workaround to get the versions CI uses.
4. Remove `legacy-plan-heading`. Add the line `<!-- patufet:plan -->` to the plans of open issues
   that do not have it.
5. Check that `AGENTS.md` / `CLAUDE.md` describe the build and test commands correctly: the
   implementer relies on them and on the CI workflows.
6. Recommended: replace `secrets: inherit` with the secret you use, in this file and in
   `patufet-mention.yml`. See [security.md](security.md#tokens).

As with any PR that edits the caller, this one gets no automatic review.
