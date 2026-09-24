# Working on patufet

> **Asked to adopt patufet in another repository?** This is not your file: read and follow
> [ADOPTING.md](ADOPTING.md). To remove it, follow [docs/uninstall.md](docs/uninstall.md).

This file is for agents changing patufet itself. [CONTRIBUTING.md](CONTRIBUTING.md) has the
full rules; the essentials:

- The repository is reusable GitHub Actions workflows (`.github/workflows/`), the prompts
  they render (`prompts/`), the helpers they run (`scripts/`), the files copied into
  consumer repositories (`templates/`) and the docs. [docs/architecture.md](docs/architecture.md)
  explains the state machine; [docs/decisions.md](docs/decisions.md) why it is built this way.
- Deterministic logic goes in `scripts/` (testable), not inline in the workflows. Filters
  on comments go in `scripts/trusted-comments.jq`: nothing untrusted may reach an agent that
  can write.
- Prompts get every label name and value through `{{placeholders}}`; never hard-code one.
- Run `tests/run.sh` (offline, stubs `gh`) and, if installed, `actionlint` and
  `shellcheck scripts/*.sh`. CI runs all three (`self-check.yml`).
- The workflows cannot run locally. A change to a workflow or a prompt is only proven by a
  real cycle on a sandbox repository (see CONTRIBUTING.md).
- Every user-visible change gets a `CHANGELOG.md` entry; commits follow Conventional Commits.
