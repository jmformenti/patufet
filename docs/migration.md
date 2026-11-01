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
3. Set `ci-checks`, `human-reviewer`, `language` in the caller (and `test-command`, only
   without CI on pull requests).
4. Open issues whose plan comment has no marker: either edit the comment and prepend the
   line `<!-- patufet:plan -->` (simplest), or set
   `legacy-plan-heading: "## Your old heading"` on `implement`, `review` and `e2e` if the old
   plans share a distinctive heading; remove it when those issues are closed.
5. Update the local `/plan-issue` command (`.claude/commands/plan-issue.md`) so it writes the
   `<!-- patufet:plan -->` marker.
6. Clean up: repository variables the old flow used (e.g. `MAX_REVIEW_CYCLES` → input
   `max-review-cycles`), dead labels, `README` section pointing here.
7. First run on `@main` while iterating on the template if needed, then switch to `@v1`.

## Upgrading

- On `@v1`: nothing to do for compatible releases; read `CHANGELOG.md` for new inputs.
- Major bump: the changelog lists the renamed inputs / new files; update the caller and the
  extension files, then change `@v1` → `@v2`.

### To the CI-aware review (opt-in)

Nothing changes until you do this, in `.github/workflows/patufet.yml`. Without CI on pull
requests, add a CI workflow first, running what `test-command` runs today.

1. `review` job: add `ci-checks: "<check names>"` and `human-reviewer: "<login>"`, remove
   `ci-check-names`, and add `actions: read` and `checks: read` to `permissions`. See
   [The CI-aware review](customization.md#the-ci-aware-review) for the names to use.
2. `implement` and `fix-review` jobs: remove `test-command`. Add `java-version` / `node-version`
   instead of any workaround to get the versions CI uses.
3. Check that `AGENTS.md` / `CLAUDE.md` describe the build and test commands correctly: the
   implementer now relies on them and on the CI workflows.

As with any PR that edits the caller, this one gets no automatic review.
