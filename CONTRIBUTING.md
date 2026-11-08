# Contributing to patufet

## Layout

| Path | What | Rule |
|---|---|---|
| `.github/workflows/{implement,review,fix-review,e2e,mention}.yml` | reusable workflows | orchestration only; logic goes in `scripts/` |
| `.github/workflows/self-check.yml` | CI of this repository | lint + offline tests |
| `prompts/*.md` | base prompts | values only through `{{placeholders}}` (see docs/customization.md) |
| `scripts/` | helpers the workflows run, and `bootstrap.sh` | bash + jq (+ python3 stdlib); no dependency the runner lacks |
| `templates/` | files copied into consumer repositories | a change here only reaches new adoptions |
| `tests/` | offline tests: `run.sh`, a `gh` stub, JSON fixtures | every script behaviour has a test |
| `ADOPTING.md`, `docs/` | user docs | kept true: `tests/run.sh` checks that every input is documented |

## Checking a change

1. `tests/run.sh` — offline, a few seconds. It stubs `gh` (`tests/stubs/gh`) and reads
   `tests/fixtures/*.json`, so it needs only bash, jq and python3. It also checks that every
   `{{placeholder}}` of a prompt is set by its workflow, that no prompt hard-codes a label
   and that every workflow input appears in the docs.
2. `actionlint` and `shellcheck scripts/*.sh templates/.github/patufet/*.sh tests/*.sh tests/stubs/gh`
   if installed; `self-check.yml` runs them on every PR with pinned versions.
3. A change to a workflow, a prompt or the flow is only proven by a real cycle. Use a
   sandbox repository whose caller points at your branch (`uses: …/implement.yml@<branch>`),
   open a trivial issue, run `/plan-issue`, and watch implement → review → fix → e2e. The
   job summaries show turns and cost per run.

To add a test, add a fixture (a real API response, trimmed) and a few `eq` / `has` lines in
`tests/run.sh`; to cover a new `gh` call, teach the stub to answer it.

## Conventions

- Commits: [Conventional Commits](https://www.conventionalcommits.org/) in English
  (`fix:`, `feat:`, `docs:`, `chore:`, `refactor:`, `test:`; `!` for breaking changes).
- Every user-visible change adds a line to `## Unreleased` in `CHANGELOG.md`.
- Workflow `run:` blocks never interpolate untrusted values with `${{ }}`: pass them through
  `env:`.
- Branch from `main`, open a PR; `self-check` must be green.

## Releasing

1. Move `## Unreleased` in `CHANGELOG.md` to `## v1.x.y — <date>`; merge.
2. Tag the merge commit and move the major tag:
   ```bash
   version=v1.2.0   # the new release
   git tag "$version" && git tag -f v1 "$version"
   git push origin "$version" && git push -f origin v1
   ```
3. Create the GitHub release, with that version's section of `CHANGELOG.md` as notes:
   ```bash
   notes=$(mktemp)
   awk -v h="## $version " 'index($0, h) == 1 {f=1; next} /^## v/ {f=0} f' CHANGELOG.md | sed '/./,$!d' > "$notes"
   gh release create "$version" --verify-tag --title "$version" --notes-file "$notes" --latest
   ```
4. Consumers on `@v1` get it on their next run; tell the ones pinned to `@v1.x.y`.

**Breaking changes** (renamed input, changed marker, new required file) normally bump the
major (`v2`, new moving tag `v2`) with migration steps in the changelog. While the only known
consumers are the maintainer's (habitus-trainer, philobiblon-ui, carabassa), they may instead be
shipped on `v1` once those are migrated; the changelog entry is then marked **Breaking** and the
minor is bumped.

## Rolling back

Point the major tag back at the previous release; consumers on `@v1` pick it up on their next
run, nothing to change on their side:

```bash
previous=v1.1.0   # the last good release
git tag -f v1 "$previous" && git push -f origin v1
```

## Pending ideas

- Distribute `/plan-issue` as a Claude Code plugin instead of a copied file.
- A scheduled smoke test: a sandbox repository that runs one trivial issue through the whole
  flow before `v1` moves.
