# Live e2e stage

Optional. `e2e.yml` runs when a PR gets the `pass` label: it starts your application on the
GitHub runner through **your** hook script, installs the Playwright Chromium browser, lets
Claude drive the app through the Playwright MCP server, and reads the verdict.

Enable it only if the whole application can be started on `ubuntu-latest` within the job
timeout (Docker Compose, a single `npm start`, an embedded DB...). Otherwise skip the job —
the flow ends at the code review `pass` and the reviewer merges.

## Hook contract

### `e2e-up.sh` (input `up-script`, default `.github/patufet/e2e-up.sh`)

- Runs with `bash`, from the repository root, with the PR head commit that got the `pass`
  label checked out (not a later push).
- Must **start** the app, **wait** until it is usable and **seed** the test data.
- Must **exit non-zero** if the app is not usable — the job fails without posting a verdict.
- Must **append `KEY=VALUE` lines** to the file `$PATUFET_E2E_ENV`. They are rendered
  into the prompt as a bullet list, so the tester knows the URL and the test credentials.
  Use throwaway credentials only: the values appear in the prompt and in the job log.

### `e2e-down.sh` (input `down-script`)

- Always runs, even when the up hook or the test failed. Stop everything; do not fail.

### `e2e.md` (input `extra-instructions-file`)

What to always exercise for this project, on top of the PR-specific functionality.

## Example (Spring Boot + Nuxt behind Docker Compose)

```bash
#!/usr/bin/env bash
set -euo pipefail
docker compose up -d --build

for _ in $(seq 1 60); do   # backend answers 400 to an empty login body once it serves
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8080/api/auth/login \
    -H 'Content-Type: application/json' -d '{}' || true)
  [ "$code" = "400" ] && break; sleep 2
done
[ "${code:-}" = "400" ] || { docker compose logs backend; exit 1; }

curl -sf -X POST http://localhost:8080/api/auth/register/runner -H 'Content-Type: application/json' \
  -d '{"email":"runner@test.local","password":"test1234","profile":{...}}'

{
  echo "APP_URL=http://localhost:3000"
  echo "RUNNER_EMAIL=runner@test.local"
  echo "RUNNER_PASSWORD=test1234"
} >> "$PATUFET_E2E_ENV"
```

## Verdict handling

The tester posts one comment whose first line is
`<!-- patufet:e2e run=<run_id>.<attempt> verdict=pass|fail -->` and returns the same verdict
as structured output. A deterministic step reads the structured verdict (or, failing that,
the marker of *this* run's comment by a trusted author) and then:

- `fail` → Claude has relabelled the PR `fail` with the App token, which re-triggers
  `fix-review` (the step repairs the label if Claude did not);
- `pass` → posts "ready for human review" mentioning `human-reviewer`.

If the Claude step fails or yields no verdict, the job fails and a warning comment is posted;
labels are left untouched.

## Inputs

| Input | Default |
|---|---|
| `up-script` | `.github/patufet/e2e-up.sh` |
| `down-script` | `.github/patufet/e2e-down.sh` |
| `extra-instructions-file` | `.github/patufet/e2e.md` |
| `human-reviewer` | `''` |
| `install-playwright` | `true` (set false if your image already has Chromium) |
| `playwright-mcp-version` | `0.0.82` — `@playwright/mcp` version; the browser installed is the one of the Playwright version it depends on |
| `allowed-tools` | `mcp__playwright__*,Bash(gh pr view:*),Bash(gh pr diff:*),Bash(gh pr comment:*),Bash(gh pr edit:*),Bash(gh issue view:*)` — no `gh pr merge`: the tester reads pages rendered by the PR's code |
| `branch-prefix`, `language`, `model`, `allowed-bots`, `claude-args-extra`, `show-full-output`, `legacy-plan-heading` | as in [customization.md](customization.md) |
| `label-pass`, `label-warning`, `label-fail` | `pass`, `warning`, `fail` |
| `max-turns` | `200` |
| `timeout-minutes` | `30` |

The Playwright install is wrapped in `timeout 300` × 3 attempts: on a real run its inner
`apt-get` hung for 27 minutes against a flaky runner mirror and ate the whole job timeout.
Both the MCP server and the browser are pinned: `@latest` changed under running flows.
