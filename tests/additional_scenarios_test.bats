#!/usr/bin/env bats

setup_file() {
  ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCENARIO_SCRIPT="${ROOT_DIR}/scripts/phase1_additional_scenarios.sh"
  SCENARIO_TMPDIR="$(mktemp -d)"
  SCENARIO_OUTPUT_DIR="${SCENARIO_TMPDIR}/reports"
  SCENARIO_JSON_FILE="${SCENARIO_TMPDIR}/additional-scenarios.json"
  TRACKED_JSON_FILE="${ROOT_DIR}/reports/evaluation/2026-03-08-phase1-additional-scenarios.json"
  TRACKED_MD_FILE="${ROOT_DIR}/reports/evaluation/2026-03-08-phase1-additional-scenarios.md"

  "${SCENARIO_SCRIPT}" --output-dir "${SCENARIO_OUTPUT_DIR}" --date "2026-03-08" > "${SCENARIO_JSON_FILE}"

  export ROOT_DIR
  export SCENARIO_SCRIPT
  export SCENARIO_TMPDIR
  export SCENARIO_OUTPUT_DIR
  export SCENARIO_JSON_FILE
  export TRACKED_JSON_FILE
  export TRACKED_MD_FILE
}

teardown_file() {
  rm -rf "${SCENARIO_TMPDIR}"
}

additional_scenarios_returns_valid_evaluation_json() { # @test
  run jq -e 'type == "object" and .version == 1 and .mode == "evaluation" and (.generated_at | type == "string") and (.scenarios | type == "array") and (.notes | type == "array")' "${SCENARIO_JSON_FILE}"
  [ "$status" -eq 0 ]
}

additional_scenarios_contains_all_three_scenario_ids() { # @test
  run jq -e '
    (.scenarios | length) == 3 and
    ([.scenarios[].id] | index("merge_conflict")) != null and
    ([.scenarios[].id] | index("ttl_expiry_doctor_fix")) != null and
    ([.scenarios[].id] | index("takeover_format_matrix")) != null
  ' "${SCENARIO_JSON_FILE}"
  [ "$status" -eq 0 ]
}

additional_scenarios_marks_each_expected_scenario_as_passed() { # @test
  run jq -e '
    [.scenarios[] | select(.id == "merge_conflict") | .passed] == [true] and
    [.scenarios[] | select(.id == "ttl_expiry_doctor_fix") | .passed] == [true] and
    [.scenarios[] | select(.id == "takeover_format_matrix") | .passed] == [true]
  ' "${SCENARIO_JSON_FILE}"
  [ "$status" -eq 0 ]
}

additional_scenarios_locks_merge_and_ttl_contract_checks() { # @test
  run jq -e '
    [.scenarios[] | select(.id == "merge_conflict") | .checks.merge_exit_code] == [1] and
    ([.scenarios[] | select(.id == "merge_conflict") | .checks.unmerged_entries_count] | first) > 0 and
    [.scenarios[] | select(.id == "merge_conflict") | .checks.conflict_detected] == [true] and
    [.scenarios[] | select(.id == "ttl_expiry_doctor_fix") | .checks.expired_detected] == [true] and
    ([.scenarios[] | select(.id == "ttl_expiry_doctor_fix") | .checks.claims_before_fix] | first) > 0 and
    [.scenarios[] | select(.id == "ttl_expiry_doctor_fix") | .checks.claims_after_fix] == [0] and
    [.scenarios[] | select(.id == "ttl_expiry_doctor_fix") | .checks.doctor_before_fix_exit_code] == [2] and
    [.scenarios[] | select(.id == "ttl_expiry_doctor_fix") | .checks.doctor_after_fix_exit_code] == [0]
  ' "${SCENARIO_JSON_FILE}"
  [ "$status" -eq 0 ]
}

additional_scenarios_records_takeover_format_matrix_exit_codes() { # @test
  run jq -e '
    .scenarios[]
    | select(.id == "takeover_format_matrix")
    | .checks.full_bundle.md == 0 and
      .checks.full_bundle.json == 0 and
      .checks.full_bundle.prompt == 0 and
      .checks.full_bundle.plan == 0 and
      .checks.evidence_only_bundle.md == 0 and
      .checks.evidence_only_bundle.json != 0 and
      .checks.evidence_only_bundle.prompt != 0 and
      .checks.evidence_only_bundle.plan != 0
  ' "${SCENARIO_JSON_FILE}"
  [ "$status" -eq 0 ]
}

additional_scenarios_writes_json_and_markdown_artifacts() { # @test
  [ -f "${SCENARIO_OUTPUT_DIR}/2026-03-08-phase1-additional-scenarios.json" ]
  [ -f "${SCENARIO_OUTPUT_DIR}/2026-03-08-phase1-additional-scenarios.md" ]

  run jq -e '.mode == "evaluation" and (.scenarios | length == 3)' "${SCENARIO_OUTPUT_DIR}/2026-03-08-phase1-additional-scenarios.json"
  [ "$status" -eq 0 ]

  run grep -F "Synthetic evaluation evidence for backlog A-004." "${SCENARIO_OUTPUT_DIR}/2026-03-08-phase1-additional-scenarios.md"
  [ "$status" -eq 0 ]
}

additional_scenarios_matches_checked_in_report_artifacts() { # @test
  run jq -S 'del(.generated_at)' "${SCENARIO_OUTPUT_DIR}/2026-03-08-phase1-additional-scenarios.json"
  [ "$status" -eq 0 ]
  local generated_json="$output"

  run jq -S 'del(.generated_at)' "${TRACKED_JSON_FILE}"
  [ "$status" -eq 0 ]
  local tracked_json="$output"

  [ "${generated_json}" = "${tracked_json}" ]

  run cmp -s "${SCENARIO_OUTPUT_DIR}/2026-03-08-phase1-additional-scenarios.md" "${TRACKED_MD_FILE}"
  [ "$status" -eq 0 ]
}
