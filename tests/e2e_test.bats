#!/usr/bin/env bats

setup() {
  MAW_BIN="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/bin/maw"
  TEST_DIR="$(mktemp -d)"
  cd "$TEST_DIR"
  REMOTE_DIR="${TEST_DIR}/remote.git"

  git init --initial-branch=main
  git config user.email "test@example.com"
  git config user.name "Test User"
  echo '{}' > package.json
  echo '# test' > yarn.lock
  git add .
  git commit -m "initial commit"
  git init --bare "$REMOTE_DIR"
  git remote add origin "$REMOTE_DIR"
  git push -u origin main
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

@test "E2E ready flow: init -> spawn -> claim -> handover -> takeover(plan) -> doctor(json)" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude --issue 10
  "$MAW_BIN" claim src/auth.ts --workspace ws1
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" handover --workspace ws1 \
    --verification-status passed \
    --summary "Ready for merge after passing verification." \
    --resume-command "bats tests/e2e_test.bats" \
    --evidence-ref "diff:HEAD~1"
  [ "$status" -eq 0 ]

  local plan
  plan="$("$MAW_BIN" takeover ws1 --format plan)"

  [ "$(echo "$plan" | jq -r '.score')" -eq 100 ]
  [ "$(echo "$plan" | jq -r '.category')" = "ready" ]
  [ "$(echo "$plan" | jq -r '.state')" = "clean" ]
  [ "$(echo "$plan" | jq -r '.workspace')" = "ws1" ]
  [ "$(echo "$plan" | jq '[.priority_actions[] | select(.action == "verify")] | length')" -eq 0 ]
  [ "$(echo "$plan" | jq '[.priority_actions[] | select(.action == "unblock")] | length')" -eq 0 ]

  run "$MAW_BIN" doctor --json --exit-code-mode multi
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    type == "object" and
    (has("version") and (.version | type == "number") and .version == 2) and
    (has("summary") and (.summary | type == "object")) and
    (has("categories") and (.categories | type == "object")) and
    (has("checks") and (.checks | type == "array")) and
    (has("health_score") and (.health_score | type == "number") and (.health_score | floor == . and . >= 0 and . <= 100))
  ' >/dev/null
}

@test "E2E caution flow: init -> spawn -> claim -> handover -> takeover(plan) -> doctor(json)" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude --issue 10
  "$MAW_BIN" claim src/auth.ts --workspace ws1
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" handover --workspace ws1 \
    --summary "Implementation in progress and waiting for verification." \
    --resume-command "bats tests/e2e_test.bats" \
    --evidence-ref "test:bats tests/e2e_test.bats"
  [ "$status" -eq 0 ]

  local plan
  plan="$("$MAW_BIN" takeover ws1 --format plan)"

  [ "$(echo "$plan" | jq -r '.score')" -eq 72 ]
  [ "$(echo "$plan" | jq -r '.category')" = "caution" ]
  [ "$(echo "$plan" | jq -r '.state')" = "clean" ]
  [ "$(echo "$plan" | jq -r '[.priority_actions[] | select(.action == "verify")] | first | .action')" = "verify" ]

  run "$MAW_BIN" doctor --json --exit-code-mode multi
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    type == "object" and
    (has("version") and (.version | type == "number") and .version == 2) and
    (has("summary") and (.summary | type == "object")) and
    (has("categories") and (.categories | type == "object")) and
    (has("checks") and (.checks | type == "array")) and
    (has("health_score") and (.health_score | type == "number") and (.health_score | floor == . and . >= 0 and . <= 100))
  ' >/dev/null
}

@test "E2E blocked flow: init -> spawn -> claim -> handover -> takeover(plan) -> doctor(json)" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude --issue 10
  "$MAW_BIN" claim src/auth.ts --workspace ws1
  mkdir -p ".maw-workspaces/ws1/src"
  echo "dirty change" > ".maw-workspaces/ws1/src/auth.ts"
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" handover --workspace ws1 \
    --verification-status failed \
    --summary "Blocked by failed verification and external dependencies." \
    --resume-command "bats tests/e2e_test.bats" \
    --risk "Critical production validation gap" \
    --risk-severity critical
  [ "$status" -eq 0 ]
  "$MAW_BIN" handover --workspace ws1 --blocked-by-type blocker --blocked-by-desc "Critical blocker"
  "$MAW_BIN" handover --workspace ws1 --blocked-by-type dependency --blocked-by-desc "Dependency update pending"
  "$MAW_BIN" handover --workspace ws1 --blocked-by-type issue --blocked-by-desc "Issue triage pending"

  local plan
  plan="$("$MAW_BIN" takeover ws1 --format plan)"

  [ "$(echo "$plan" | jq -r '.score')" -eq 20 ]
  [ "$(echo "$plan" | jq -r '.category')" = "blocked" ]
  [ "$(echo "$plan" | jq -r '.state')" = "dirty" ]
  [ "$(echo "$plan" | jq -r '.blockers_count')" -eq 3 ]
  [ "$(echo "$plan" | jq '[.priority_actions[] | select(.action == "verify")] | length')" -ge 1 ]
  [ "$(echo "$plan" | jq '[.priority_actions[] | select(.action == "unblock")] | length')" -ge 1 ]

  run "$MAW_BIN" doctor --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    type == "object" and
    (has("version") and (.version | type == "number") and .version == 2) and
    (has("summary") and (.summary | type == "object")) and
    (has("categories") and (.categories | type == "object")) and
    (has("checks") and (.checks | type == "array")) and
    (has("health_score") and (.health_score | type == "number") and (.health_score | floor == . and . >= 0 and . <= 100))
  ' >/dev/null
}
