#!/usr/bin/env bats

setup_file() {
  ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SAMPLE_SCRIPT="${ROOT_DIR}/scripts/phase1_handover_samples.sh"
  SAMPLE_TMPDIR="$(mktemp -d)"
  SAMPLE_OUTPUT_DIR="${SAMPLE_TMPDIR}/reports"
  SAMPLE_JSON_FILE="${SAMPLE_TMPDIR}/handover-samples.json"
  SOURCE_FIXTURE_DIR="${ROOT_DIR}/reports/evaluation/handovers"
  TRACKED_JSON_FILE="${ROOT_DIR}/reports/evaluation/2026-03-08-handover-samples.json"
  TRACKED_MD_FILE="${ROOT_DIR}/reports/evaluation/2026-03-08-handover-samples.md"

  "${SAMPLE_SCRIPT}" --source-dir "${SOURCE_FIXTURE_DIR}" --output-dir "${SAMPLE_OUTPUT_DIR}" --date "2026-03-08" > "${SAMPLE_JSON_FILE}"

  export ROOT_DIR
  export SAMPLE_SCRIPT
  export SAMPLE_TMPDIR
  export SAMPLE_OUTPUT_DIR
  export SAMPLE_JSON_FILE
  export SOURCE_FIXTURE_DIR
  export TRACKED_JSON_FILE
  export TRACKED_MD_FILE
}

teardown_file() {
  rm -rf "${SAMPLE_TMPDIR}"
}

handover_samples_returns_valid_json() { # @test
  run jq -e 'type == "object" and .version == 1 and .mode == "handover_samples" and (.generated_at | type == "string") and (.samples | type == "array") and (.notes | type == "array")' "${SAMPLE_JSON_FILE}"
  [ "$status" -eq 0 ]
}

handover_samples_contains_expected_workspaces() { # @test
  run jq -e '
    (.samples | length) >= 3 and
    ([.samples[].workspace] | index("issue10_t2_docs")) != null and
    ([.samples[].workspace] | index("issue10_t3_pr")) != null and
    ([.samples[].workspace] | index("issue10_t6_pr")) != null
  ' "${SAMPLE_JSON_FILE}"
  [ "$status" -eq 0 ]
}

handover_samples_enforces_summary_and_evidence_refs() { # @test
  run jq -e 'all(.samples[]; (.summary != "") and (.evidence_refs_count >= 1))' "${SAMPLE_JSON_FILE}"
  [ "$status" -eq 0 ]
}

handover_samples_writes_json_and_markdown_reports() { # @test
  [ -f "${SAMPLE_OUTPUT_DIR}/2026-03-08-handover-samples.json" ]
  [ -f "${SAMPLE_OUTPUT_DIR}/2026-03-08-handover-samples.md" ]
  [ -f "${SAMPLE_OUTPUT_DIR}/handovers/ws-issue10_t2_docs.json" ]
  [ -f "${SAMPLE_OUTPUT_DIR}/handovers/ws-issue10_t3_pr.json" ]
  [ -f "${SAMPLE_OUTPUT_DIR}/handovers/ws-issue10_t6_pr.json" ]
}

handover_samples_tracked_copies_exclude_volatile_fields() { # @test
  run jq -e '
    (has("claims") | not) and
    (has("diff") | not) and
    (has("diff_stat") | not) and
    (has("log") | not) and
    (has("resume_commands") | not)
  ' "${SAMPLE_OUTPUT_DIR}/handovers/ws-issue10_t2_docs.json"
  [ "$status" -eq 0 ]

  run jq -e '
    (has("claims") | not) and
    (has("diff") | not) and
    (has("diff_stat") | not) and
    (has("log") | not) and
    (has("resume_commands") | not)
  ' "${SAMPLE_OUTPUT_DIR}/handovers/ws-issue10_t3_pr.json"
  [ "$status" -eq 0 ]

  run jq -e '
    (has("claims") | not) and
    (has("diff") | not) and
    (has("diff_stat") | not) and
    (has("log") | not) and
    (has("resume_commands") | not)
  ' "${SAMPLE_OUTPUT_DIR}/handovers/ws-issue10_t6_pr.json"
  [ "$status" -eq 0 ]
}

handover_samples_tracked_copies_match_checked_in_fixtures() { # @test
  run cmp -s "${SAMPLE_OUTPUT_DIR}/handovers/ws-issue10_t2_docs.json" "${SOURCE_FIXTURE_DIR}/ws-issue10_t2_docs.json"
  [ "$status" -eq 0 ]

  run cmp -s "${SAMPLE_OUTPUT_DIR}/handovers/ws-issue10_t3_pr.json" "${SOURCE_FIXTURE_DIR}/ws-issue10_t3_pr.json"
  [ "$status" -eq 0 ]

  run cmp -s "${SAMPLE_OUTPUT_DIR}/handovers/ws-issue10_t6_pr.json" "${SOURCE_FIXTURE_DIR}/ws-issue10_t6_pr.json"
  [ "$status" -eq 0 ]
}

handover_samples_tracked_copies_lock_projected_schema() { # @test
  run jq -e '
    (.version | type == "number") and
    (.workspace | type == "string") and
    (.branch | type == "string") and
    (.agent | type == "string") and
    (.state | type == "string") and
    (.summary | type == "string") and
    (.summary != "") and
    (.evidence_refs | type == "array") and
    all(.evidence_refs[]; type == "string") and
    (.verification_status | type == "string") and
    (.blocked_by | type == "array")
  ' "${SAMPLE_OUTPUT_DIR}/handovers/ws-issue10_t2_docs.json"
  [ "$status" -eq 0 ]
}

handover_samples_matches_checked_in_reports() { # @test
  run jq -S 'del(.generated_at)' "${SAMPLE_OUTPUT_DIR}/2026-03-08-handover-samples.json"
  [ "$status" -eq 0 ]
  local generated_json="$output"

  run jq -S 'del(.generated_at)' "${TRACKED_JSON_FILE}"
  [ "$status" -eq 0 ]
  local tracked_json="$output"

  [ "${generated_json}" = "${tracked_json}" ]

  run cmp -s "${SAMPLE_OUTPUT_DIR}/2026-03-08-handover-samples.md" "${TRACKED_MD_FILE}"
  [ "$status" -eq 0 ]
}
