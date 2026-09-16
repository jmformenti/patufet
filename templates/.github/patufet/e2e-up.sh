#!/usr/bin/env bash
# patufet e2e hook: start the application on the GitHub runner, wait until
# it answers, seed the test data, and export what the tester needs.
#
# Contract (see https://github.com/jmformenti/patufet/blob/main/docs/e2e.md):
#   - Runs from the repository root with the PR branch checked out.
#   - Must exit non-zero if the app is not usable (the job then fails, no verdict).
#   - Must append KEY=VALUE lines to the file named by $PATUFET_E2E_ENV: URLs
#     and TEST credentials only (they end up in the prompt and in the job log).
set -euo pipefail

# 1. Start (adapt to your stack: docker compose, npm start &, ./gradlew bootRun &, ...)
docker compose up -d --build

# 2. Wait for readiness
echo "Waiting for http://localhost:3000 ..."
for _ in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/ || true)
  [ "$code" = "200" ] && break
  sleep 2
done
if [ "${code:-}" != "200" ]; then
  echo "The application did not start in time"
  docker compose logs
  exit 1
fi

# 3. Seed test data (register users, load fixtures...)
# curl -sf -X POST http://localhost:8080/api/auth/register -H 'Content-Type: application/json' \
#   -d '{"email":"tester@example.local","password":"test1234"}'

# 4. Export what the tester needs
{
  echo "APP_URL=http://localhost:3000"
  # echo "TEST_USER_EMAIL=tester@example.local"
  # echo "TEST_USER_PASSWORD=test1234"
} >> "$PATUFET_E2E_ENV"
