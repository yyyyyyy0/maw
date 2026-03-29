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

handover_samples_preserves_full_relative_source_ref() { # @test
  local relative_json_file
  local relative_output_dir
  relative_json_file="${SAMPLE_TMPDIR}/handover-samples-relative.json"
  relative_output_dir="${SAMPLE_TMPDIR}/reports-relative"

  run bash -lc 'cd "$1" && "$2" --source-dir reports/evaluation/handovers --output-dir "$3" --date 2026-03-08 > "$4"' _ \
    "${ROOT_DIR}" "${SAMPLE_SCRIPT}" "${relative_output_dir}" "${relative_json_file}"
  [ "$status" -eq 0 ]

  run jq -e '
    [.samples[].source_ref] == [
      "reports/evaluation/handovers/ws-issue10_t2_docs.json",
      "reports/evaluation/handovers/ws-issue10_t3_pr.json",
      "reports/evaluation/handovers/ws-issue10_t6_pr.json"
    ]
  ' "${relative_json_file}"
  [ "$status" -eq 0 ]
}

handover_samples_prefers_operational_root_over_tracked_fixtures() { # @test
  local temp_repo
  local temp_output_dir
  local temp_json

  temp_repo="${SAMPLE_TMPDIR}/precedence-repo"
  temp_output_dir="${SAMPLE_TMPDIR}/precedence-output"
  temp_json="${SAMPLE_TMPDIR}/precedence.json"

  mkdir -p "${temp_repo}/scripts" "${temp_repo}/lib" "${temp_repo}/reports/evaluation/handovers" "${temp_repo}/.maw/handovers"
  cp "${SAMPLE_SCRIPT}" "${temp_repo}/scripts/phase1_handover_samples.sh"
  cp "${ROOT_DIR}/lib/core.sh" "${ROOT_DIR}/lib/validate.sh" "${temp_repo}/lib/"
  cp "${SOURCE_FIXTURE_DIR}/"*.json "${temp_repo}/reports/evaluation/handovers/"
  cp "${SOURCE_FIXTURE_DIR}/"*.json "${temp_repo}/.maw/handovers/"

  jq '.summary = "OPERATIONS-FIRST SAMPLE"' \
    "${temp_repo}/.maw/handovers/ws-issue10_t2_docs.json" > "${temp_repo}/.maw/handovers/ws-issue10_t2_docs.json.tmp"
  mv "${temp_repo}/.maw/handovers/ws-issue10_t2_docs.json.tmp" "${temp_repo}/.maw/handovers/ws-issue10_t2_docs.json"

  run bash -lc 'cd "$1" && "$2" --output-dir "$3" --date 2026-03-08 > "$4"' _ \
    "${temp_repo}" "${temp_repo}/scripts/phase1_handover_samples.sh" "${temp_output_dir}" "${temp_json}"
  [ "$status" -eq 0 ]

  run jq -e '
    [.samples[] | select(.workspace == "issue10_t2_docs") | .summary] == ["OPERATIONS-FIRST SAMPLE"] and
    [.samples[] | select(.workspace == "issue10_t2_docs") | .source_ref] == [".maw/handovers/ws-issue10_t2_docs.json"]
  ' "${temp_json}"
  [ "$status" -eq 0 ]
}

handover_samples_ignores_parent_maw_when_repo_root_has_no_operational_samples() { # @test
  local parent_dir
  local temp_repo
  local temp_output_dir
  local temp_json

  parent_dir="${SAMPLE_TMPDIR}/outer"
  temp_repo="${parent_dir}/repo"
  temp_output_dir="${SAMPLE_TMPDIR}/fallback-output"
  temp_json="${SAMPLE_TMPDIR}/fallback.json"

  mkdir -p "${parent_dir}/.maw/handovers" "${temp_repo}/scripts" "${temp_repo}/lib" "${temp_repo}/reports/evaluation/handovers"
  cp "${SAMPLE_SCRIPT}" "${temp_repo}/scripts/phase1_handover_samples.sh"
  cp "${ROOT_DIR}/lib/core.sh" "${ROOT_DIR}/lib/validate.sh" "${temp_repo}/lib/"
  cp "${SOURCE_FIXTURE_DIR}/"*.json "${temp_repo}/reports/evaluation/handovers/"
  cp "${SOURCE_FIXTURE_DIR}/ws-issue10_t2_docs.json" "${parent_dir}/.maw/handovers/ws-issue10_t2_docs.json"

  jq '.summary = "UNRELATED PARENT SAMPLE"' \
    "${parent_dir}/.maw/handovers/ws-issue10_t2_docs.json" > "${parent_dir}/.maw/handovers/ws-issue10_t2_docs.json.tmp"
  mv "${parent_dir}/.maw/handovers/ws-issue10_t2_docs.json.tmp" "${parent_dir}/.maw/handovers/ws-issue10_t2_docs.json"

  run bash -lc 'cd "$1" && "$2" --output-dir "$3" --date 2026-03-08 > "$4"' _ \
    "${temp_repo}" "${temp_repo}/scripts/phase1_handover_samples.sh" "${temp_output_dir}" "${temp_json}"
  [ "$status" -eq 0 ]

  run jq -e '
    [.samples[] | select(.workspace == "issue10_t2_docs") | .summary] == ["Issue 10 T2 docs: fixed the public doctor --json contract in commands and CI docs, including a new English doctor-ci guide"] and
    [.samples[] | select(.workspace == "issue10_t2_docs") | .source_ref] == ["reports/evaluation/handovers/ws-issue10_t2_docs.json"]
  ' "${temp_json}"
  [ "$status" -eq 0 ]
}

handover_samples_rejects_empty_evidence_refs_entries() { # @test
  local invalid_source_dir

  invalid_source_dir="${SAMPLE_TMPDIR}/invalid-source"
  mkdir -p "${invalid_source_dir}"
  cp "${SOURCE_FIXTURE_DIR}/"*.json "${invalid_source_dir}/"

  jq '.evidence_refs = [""]' \
    "${invalid_source_dir}/ws-issue10_t2_docs.json" > "${invalid_source_dir}/ws-issue10_t2_docs.json.tmp"
  mv "${invalid_source_dir}/ws-issue10_t2_docs.json.tmp" "${invalid_source_dir}/ws-issue10_t2_docs.json"

  run "${SAMPLE_SCRIPT}" --source-dir "${invalid_source_dir}" --output-dir "${SAMPLE_TMPDIR}/invalid-output" --date "2026-03-08"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"invalid handover sample"* ]]
}

handover_samples_rejects_noncanonical_handover_fields() { # @test
  local invalid_source_dir

  invalid_source_dir="${SAMPLE_TMPDIR}/invalid-canonical-source"
  mkdir -p "${invalid_source_dir}"
  cp "${SOURCE_FIXTURE_DIR}/"*.json "${invalid_source_dir}/"

  jq '.verification_status = "done" | .blocked_by = [{"type":"dependency","description":"missing resolved"}]' \
    "${invalid_source_dir}/ws-issue10_t2_docs.json" > "${invalid_source_dir}/ws-issue10_t2_docs.json.tmp"
  mv "${invalid_source_dir}/ws-issue10_t2_docs.json.tmp" "${invalid_source_dir}/ws-issue10_t2_docs.json"

  run "${SAMPLE_SCRIPT}" --source-dir "${invalid_source_dir}" --output-dir "${SAMPLE_TMPDIR}/invalid-canonical-output" --date "2026-03-08"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"invalid handover sample"* ]]
}

handover_samples_does_not_partially_overwrite_outputs_on_invalid_source() { # @test
  local invalid_source_dir
  local stable_output_dir

  invalid_source_dir="${SAMPLE_TMPDIR}/partial-invalid-source"
  stable_output_dir="${SAMPLE_TMPDIR}/partial-output"
  mkdir -p "${invalid_source_dir}"
  cp "${SOURCE_FIXTURE_DIR}/"*.json "${invalid_source_dir}/"

  "${SAMPLE_SCRIPT}" --source-dir "${SOURCE_FIXTURE_DIR}" --output-dir "${stable_output_dir}" --date "2026-03-08" > /dev/null

  jq '.summary = "SHOULD NOT LAND"' \
    "${invalid_source_dir}/ws-issue10_t2_docs.json" > "${invalid_source_dir}/ws-issue10_t2_docs.json.tmp"
  mv "${invalid_source_dir}/ws-issue10_t2_docs.json.tmp" "${invalid_source_dir}/ws-issue10_t2_docs.json"
  jq '.summary = ""' \
    "${invalid_source_dir}/ws-issue10_t3_pr.json" > "${invalid_source_dir}/ws-issue10_t3_pr.json.tmp"
  mv "${invalid_source_dir}/ws-issue10_t3_pr.json.tmp" "${invalid_source_dir}/ws-issue10_t3_pr.json"

  run "${SAMPLE_SCRIPT}" --source-dir "${invalid_source_dir}" --output-dir "${stable_output_dir}" --date "2026-03-08"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"invalid handover sample"* ]]

  run jq -r '.summary' "${stable_output_dir}/handovers/ws-issue10_t2_docs.json"
  [ "$status" -eq 0 ]
  [ "${output}" = "Issue 10 T2 docs: fixed the public doctor --json contract in commands and CI docs, including a new English doctor-ci guide" ]
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

handover_samples_preserves_full_absolute_source_ref() { # @test
  local abs_source_dir
  local abs_output_dir
  local abs_json_file

  abs_source_dir="${SAMPLE_TMPDIR}/abs-source"
  abs_output_dir="${SAMPLE_TMPDIR}/abs-output"
  abs_json_file="${SAMPLE_TMPDIR}/abs-samples.json"

  mkdir -p "${abs_source_dir}"
  cp "${SOURCE_FIXTURE_DIR}/"*.json "${abs_source_dir}/"

  run "${SAMPLE_SCRIPT}" --source-dir "${abs_source_dir}" --output-dir "${abs_output_dir}" --date "2026-03-08"
  [ "$status" -eq 0 ]

  run jq -r '.samples[0].source_ref' "${abs_output_dir}/2026-03-08-handover-samples.json"
  [ "$status" -eq 0 ]
  [[ "${output}" == "${abs_source_dir}/ws-issue10_t2_docs.json" ]]
}

handover_samples_rejects_workspace_mismatch() { # @test
  local mismatch_source_dir

  mismatch_source_dir="${SAMPLE_TMPDIR}/mismatch-source"
  mkdir -p "${mismatch_source_dir}"
  cp "${SOURCE_FIXTURE_DIR}/"*.json "${mismatch_source_dir}/"

  # Copy t3 payload into t2 slot
  cp "${SOURCE_FIXTURE_DIR}/ws-issue10_t3_pr.json" "${mismatch_source_dir}/ws-issue10_t2_docs.json"

  run "${SAMPLE_SCRIPT}" --source-dir "${mismatch_source_dir}" --output-dir "${SAMPLE_TMPDIR}/mismatch-output" --date "2026-03-08"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"workspace mismatch"* ]]
}

handover_samples_defaults_missing_blocked_by_to_empty_array() { # @test
  local no_blocked_by_dir
  local no_blocked_by_output

  no_blocked_by_dir="${SAMPLE_TMPDIR}/no-blocked-by-source"
  no_blocked_by_output="${SAMPLE_TMPDIR}/no-blocked-by-output"
  mkdir -p "${no_blocked_by_dir}"
  cp "${SOURCE_FIXTURE_DIR}/"*.json "${no_blocked_by_dir}/"

  jq 'del(.blocked_by)' \
    "${no_blocked_by_dir}/ws-issue10_t2_docs.json" > "${no_blocked_by_dir}/ws-issue10_t2_docs.json.tmp"
  mv "${no_blocked_by_dir}/ws-issue10_t2_docs.json.tmp" "${no_blocked_by_dir}/ws-issue10_t2_docs.json"

  run "${SAMPLE_SCRIPT}" --source-dir "${no_blocked_by_dir}" --output-dir "${no_blocked_by_output}" --date "2026-03-08"
  [ "$status" -eq 0 ]

  run jq -e '.blocked_by | type == "array" and length == 0' "${no_blocked_by_output}/handovers/ws-issue10_t2_docs.json"
  [ "$status" -eq 0 ]
}

handover_samples_resolves_relative_source_dir_from_cwd() { # @test
  local cwd_source_dir
  local cwd_output_dir
  local cwd_json_file

  cwd_source_dir="${SAMPLE_TMPDIR}/cwd-source"
  cwd_output_dir="${SAMPLE_TMPDIR}/cwd-output"
  cwd_json_file="${SAMPLE_TMPDIR}/cwd-samples.json"

  mkdir -p "${cwd_source_dir}/handovers"
  cp "${SOURCE_FIXTURE_DIR}/"*.json "${cwd_source_dir}/handovers/"

  run bash -lc 'cd "$1" && "$2" --source-dir handovers --output-dir "$3" --date 2026-03-08 > "$4"' _ \
    "${cwd_source_dir}" "${SAMPLE_SCRIPT}" "${cwd_output_dir}" "${cwd_json_file}"
  [ "$status" -eq 0 ]

  run jq -e '(.samples | length) >= 3' "${cwd_json_file}"
  [ "$status" -eq 0 ]
}

handover_samples_rejects_non_integer_version() { # @test
  local bad_version_dir

  bad_version_dir="${SAMPLE_TMPDIR}/bad-version-source"
  mkdir -p "${bad_version_dir}"
  cp "${SOURCE_FIXTURE_DIR}/"*.json "${bad_version_dir}/"

  jq '.version = 2.5' \
    "${bad_version_dir}/ws-issue10_t2_docs.json" > "${bad_version_dir}/ws-issue10_t2_docs.json.tmp"
  mv "${bad_version_dir}/ws-issue10_t2_docs.json.tmp" "${bad_version_dir}/ws-issue10_t2_docs.json"

  run "${SAMPLE_SCRIPT}" --source-dir "${bad_version_dir}" --output-dir "${SAMPLE_TMPDIR}/bad-version-output" --date "2026-03-08"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"invalid handover sample"* ]]
}

handover_samples_rejects_negative_version() { # @test
  local neg_version_dir

  neg_version_dir="${SAMPLE_TMPDIR}/neg-version-source"
  mkdir -p "${neg_version_dir}"
  cp "${SOURCE_FIXTURE_DIR}/"*.json "${neg_version_dir}/"

  jq '.version = -1' \
    "${neg_version_dir}/ws-issue10_t2_docs.json" > "${neg_version_dir}/ws-issue10_t2_docs.json.tmp"
  mv "${neg_version_dir}/ws-issue10_t2_docs.json.tmp" "${neg_version_dir}/ws-issue10_t2_docs.json"

  run "${SAMPLE_SCRIPT}" --source-dir "${neg_version_dir}" --output-dir "${SAMPLE_TMPDIR}/neg-version-output" --date "2026-03-08"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"invalid handover sample"* ]]
}

handover_samples_rejects_scalar_blocked_by() { # @test
  local bad_blocked_dir

  bad_blocked_dir="${SAMPLE_TMPDIR}/bad-blocked-source"
  mkdir -p "${bad_blocked_dir}"
  cp "${SOURCE_FIXTURE_DIR}/"*.json "${bad_blocked_dir}/"

  jq '.blocked_by = "oops"' \
    "${bad_blocked_dir}/ws-issue10_t2_docs.json" > "${bad_blocked_dir}/ws-issue10_t2_docs.json.tmp"
  mv "${bad_blocked_dir}/ws-issue10_t2_docs.json.tmp" "${bad_blocked_dir}/ws-issue10_t2_docs.json"

  run "${SAMPLE_SCRIPT}" --source-dir "${bad_blocked_dir}" --output-dir "${SAMPLE_TMPDIR}/bad-blocked-output" --date "2026-03-08"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"invalid handover sample"* ]]
}

handover_samples_rejects_numeric_blocked_by_entries() { # @test
  local bad_entries_dir

  bad_entries_dir="${SAMPLE_TMPDIR}/bad-entries-source"
  mkdir -p "${bad_entries_dir}"
  cp "${SOURCE_FIXTURE_DIR}/"*.json "${bad_entries_dir}/"

  jq '.blocked_by = [42]' \
    "${bad_entries_dir}/ws-issue10_t2_docs.json" > "${bad_entries_dir}/ws-issue10_t2_docs.json.tmp"
  mv "${bad_entries_dir}/ws-issue10_t2_docs.json.tmp" "${bad_entries_dir}/ws-issue10_t2_docs.json"

  run "${SAMPLE_SCRIPT}" --source-dir "${bad_entries_dir}" --output-dir "${SAMPLE_TMPDIR}/bad-entries-output" --date "2026-03-08"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"invalid handover sample"* ]]
}

handover_samples_preserves_unrelated_files_in_output_dir() { # @test
  local preserve_output_dir

  preserve_output_dir="${SAMPLE_TMPDIR}/preserve-output"
  mkdir -p "${preserve_output_dir}/handovers"
  echo "keep me" > "${preserve_output_dir}/handovers/README.md"

  run "${SAMPLE_SCRIPT}" --source-dir "${SOURCE_FIXTURE_DIR}" --output-dir "${preserve_output_dir}" --date "2026-03-08"
  [ "$status" -eq 0 ]

  [ -f "${preserve_output_dir}/handovers/README.md" ]
  [ "$(cat "${preserve_output_dir}/handovers/README.md")" = "keep me" ]
  [ -f "${preserve_output_dir}/handovers/ws-issue10_t2_docs.json" ]
}

handover_samples_falls_back_when_operational_dir_lacks_samples() { # @test
  local temp_repo
  local temp_output_dir
  local temp_json

  temp_repo="${SAMPLE_TMPDIR}/fallback-empty-maw"
  temp_output_dir="${SAMPLE_TMPDIR}/fallback-empty-output"
  temp_json="${SAMPLE_TMPDIR}/fallback-empty.json"

  mkdir -p "${temp_repo}/scripts" "${temp_repo}/lib" "${temp_repo}/reports/evaluation/handovers" "${temp_repo}/.maw/handovers"
  cp "${SAMPLE_SCRIPT}" "${temp_repo}/scripts/phase1_handover_samples.sh"
  cp "${ROOT_DIR}/lib/core.sh" "${ROOT_DIR}/lib/validate.sh" "${temp_repo}/lib/"
  cp "${SOURCE_FIXTURE_DIR}/"*.json "${temp_repo}/reports/evaluation/handovers/"
  # .maw/handovers exists but is empty — should fall back to reports/evaluation/handovers

  run bash -lc 'cd "$1" && "$2" --output-dir "$3" --date 2026-03-08 > "$4"' _ \
    "${temp_repo}" "${temp_repo}/scripts/phase1_handover_samples.sh" "${temp_output_dir}" "${temp_json}"
  [ "$status" -eq 0 ]

  run jq -e '
    [.samples[0].source_ref] == ["reports/evaluation/handovers/ws-issue10_t2_docs.json"]
  ' "${temp_json}"
  [ "$status" -eq 0 ]
}

handover_samples_rejects_v1_bundles() { # @test
  local v1_source_dir

  v1_source_dir="${SAMPLE_TMPDIR}/v1-source"
  mkdir -p "${v1_source_dir}"
  cp "${SOURCE_FIXTURE_DIR}/"*.json "${v1_source_dir}/"

  jq '.version = 1' \
    "${v1_source_dir}/ws-issue10_t2_docs.json" > "${v1_source_dir}/ws-issue10_t2_docs.json.tmp"
  mv "${v1_source_dir}/ws-issue10_t2_docs.json.tmp" "${v1_source_dir}/ws-issue10_t2_docs.json"

  run "${SAMPLE_SCRIPT}" --source-dir "${v1_source_dir}" --output-dir "${SAMPLE_TMPDIR}/v1-output" --date "2026-03-08"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"invalid handover sample"* ]]
}
