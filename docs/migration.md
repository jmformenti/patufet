# Adopting patufet

## In a new repository

Run `scripts/bootstrap.sh` (see README quick start), fill in the `TODO`s, commit. Open a
small issue (a text change, a test) and run one full cycle before trusting it with real work.

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
3. Set `test-command`, `ci-check-names`, `human-reviewer`, `language` in the caller.
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
