#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MAW_BIN="${REPO_ROOT}/bin/maw"

OUTPUT_DIR=""
OUTPUT_DATE="$(date -u +"%Y-%m-%d")"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: phase1_metrics.sh [--output-dir <dir>] [--date <YYYY-MM-DD>]

Generate phase1 proxy metrics from synthetic maw scenarios.

Options:
  --output-dir <dir>   Write JSON and Markdown artifacts to the directory
  --date <YYYY-MM-DD>  Override the artifact filename date (UTC date by default)
  -h, --help           Show this help
EOF
}

require_tools() {
  local tool=""
  for tool in git jq; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      echo "missing required tool: ${tool}" >&2
      exit 1
    fi
  done

  if [[ ! -x "${MAW_BIN}" ]]; then
    echo "maw executable not found: ${MAW_BIN}" >&2
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output-dir)
        [[ $# -ge 2 ]] || {
          echo "--output-dir requires a value" >&2
          exit 1
        }
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --date)
        [[ $# -ge 2 ]] || {
          echo "--date requires a value" >&2
          exit 1
        }
        if [[ ! "$2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
          echo "invalid --date value: $2" >&2
          exit 1
        fi
        OUTPUT_DATE="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

meta_get() {
  local file="$1"
  local key="$2"
  awk -F= -v lookup="$key" '$1 == lookup { print substr($0, length($1) + 2) }' "$file"
}

ratio_value() {
  local numerator="$1"
  local denominator="$2"
  jq -n --argjson n "$numerator" --argjson d "$denominator" \
    'if $d == 0 then 0 else ($n / $d) end'
}

average_value() {
  local total="$1"
  local count="$2"
  jq -n --argjson total "$total" --argjson count "$count" \
    'if $count == 0 then 0 else ($total / $count) end'
}

fail_with_context() {
  local message="$1"
  local json_file="${2:-}"
  local log_file="${3:-}"

  echo "${message}" >&2
  if [[ -n "${json_file}" && -f "${json_file}" ]]; then
    echo "--- scenario output ---" >&2
    cat "${json_file}" >&2
  fi
  if [[ -n "${log_file}" && -f "${log_file}" ]]; then
    echo "--- command stderr ---" >&2
    cat "${log_file}" >&2
  fi
  exit 1
}

require_jq() {
  local json_file="$1"
  local jq_filter="$2"
  local message="$3"
  local log_file="${4:-}"

  if ! jq -e "${jq_filter}" "${json_file}" >/dev/null 2>&1; then
    fail_with_context "${message}" "${json_file}" "${log_file}"
  fi
}

create_fixture_repo() {
  local scenario_dir="$1"
  local repo_dir="${scenario_dir}/repo"
  local remote_dir="${scenario_dir}/remote.git"

  mkdir -p "${scenario_dir}"

  (
    cd "${scenario_dir}"
    mkdir -p repo
    cd repo

    if git init --initial-branch=main >/dev/null 2>&1; then
      :
    else
      git init >/dev/null 2>&1
      git branch -m main >/dev/null 2>&1
    fi
    git config user.email "test@example.com"
    git config user.name "Test User"
    printf '{}\n' > package.json
    printf '# test\n' > yarn.lock
    git add package.json yarn.lock
    git commit -m "initial commit" >/dev/null 2>&1
    git init --bare "${remote_dir}" >/dev/null 2>&1
    git remote add origin "${remote_dir}"
    git push -u origin main >/dev/null 2>&1
  )
}

run_ready_scenario() {
  local scenario_dir="${TMP_DIR}/ready"
  local repo_dir="${scenario_dir}/repo"
  local meta_file="${scenario_dir}/meta.env"
  local plan_file="${scenario_dir}/plan.json"
  local doctor_file="${scenario_dir}/doctor.json"
  local handover_file="${scenario_dir}/handover.json"

  create_fixture_repo "${scenario_dir}"

  (
    cd "${repo_dir}"

    local start_ts end_ts takeover_status doctor_status category
    local takeover_log="${scenario_dir}/takeover.stderr"
    local doctor_log="${scenario_dir}/doctor.stderr"

    "${MAW_BIN}" init >/dev/null 2>&1
    "${MAW_BIN}" spawn ws1 --agent claude --issue 10 >/dev/null 2>&1
    "${MAW_BIN}" claim src/auth.ts --workspace ws1 >/dev/null 2>&1

    start_ts="$(date +%s)"
    "${MAW_BIN}" handover --workspace ws1 >/dev/null 2>&1
    "${MAW_BIN}" handover --workspace ws1 \
      --verification-status passed \
      --summary "Ready for merge after passing verification." \
      --resume-command "bats tests/e2e_test.bats" \
      --evidence-ref "diff:HEAD~1" >/dev/null 2>&1

    if "${MAW_BIN}" takeover ws1 --format plan > "${plan_file}" 2> "${takeover_log}"; then
      takeover_status=0
    else
      takeover_status=$?
      fail_with_context "ready scenario: takeover(plan) failed with status ${takeover_status}" "${plan_file}" "${takeover_log}"
    fi
    require_jq "${plan_file}" 'type == "object" and .category == "ready" and .score == 100 and .workspace == "ws1"' \
      "ready scenario: unexpected takeover(plan) output" "${takeover_log}"

    if "${MAW_BIN}" doctor --json --exit-code-mode multi > "${doctor_file}" 2> "${doctor_log}"; then
      doctor_status=0
    else
      doctor_status=$?
      fail_with_context "ready scenario: doctor(json multi) failed with status ${doctor_status}" "${doctor_file}" "${doctor_log}"
    fi
    require_jq "${doctor_file}" 'type == "object" and (.checks | type == "array") and (.summary | type == "object")' \
      "ready scenario: doctor(json multi) did not return the expected JSON contract" "${doctor_log}"

    end_ts="$(date +%s)"
    cp ".maw/handovers/ws-ws1.json" "${handover_file}"
    category="$(jq -r '.category // ""' "${plan_file}")"

    cat > "${meta_file}" <<EOF
takeover_status=${takeover_status}
doctor_status=${doctor_status}
duration_seconds=$((end_ts - start_ts))
category=${category}
EOF
  )
}

run_caution_scenario() {
  local scenario_dir="${TMP_DIR}/caution"
  local repo_dir="${scenario_dir}/repo"
  local meta_file="${scenario_dir}/meta.env"
  local plan_file="${scenario_dir}/plan.json"
  local doctor_file="${scenario_dir}/doctor.json"
  local handover_file="${scenario_dir}/handover.json"

  create_fixture_repo "${scenario_dir}"

  (
    cd "${repo_dir}"

    local start_ts end_ts takeover_status doctor_status category
    local takeover_log="${scenario_dir}/takeover.stderr"
    local doctor_log="${scenario_dir}/doctor.stderr"

    "${MAW_BIN}" init >/dev/null 2>&1
    "${MAW_BIN}" spawn ws1 --agent claude --issue 10 >/dev/null 2>&1
    "${MAW_BIN}" claim src/auth.ts --workspace ws1 >/dev/null 2>&1

    start_ts="$(date +%s)"
    "${MAW_BIN}" handover --workspace ws1 >/dev/null 2>&1
    "${MAW_BIN}" handover --workspace ws1 \
      --summary "Implementation in progress and waiting for verification." \
      --resume-command "bats tests/e2e_test.bats" \
      --evidence-ref "test:bats tests/e2e_test.bats" >/dev/null 2>&1

    if "${MAW_BIN}" takeover ws1 --format plan > "${plan_file}" 2> "${takeover_log}"; then
      takeover_status=0
    else
      takeover_status=$?
      fail_with_context "caution scenario: takeover(plan) failed with status ${takeover_status}" "${plan_file}" "${takeover_log}"
    fi
    require_jq "${plan_file}" 'type == "object" and .category == "caution" and .score == 72 and .workspace == "ws1"' \
      "caution scenario: unexpected takeover(plan) output" "${takeover_log}"

    if "${MAW_BIN}" doctor --json --exit-code-mode multi > "${doctor_file}" 2> "${doctor_log}"; then
      doctor_status=0
    else
      doctor_status=$?
      fail_with_context "caution scenario: doctor(json multi) failed with status ${doctor_status}" "${doctor_file}" "${doctor_log}"
    fi
    require_jq "${doctor_file}" 'type == "object" and (.checks | type == "array") and (.summary | type == "object")' \
      "caution scenario: doctor(json multi) did not return the expected JSON contract" "${doctor_log}"

    end_ts="$(date +%s)"
    cp ".maw/handovers/ws-ws1.json" "${handover_file}"
    category="$(jq -r '.category // ""' "${plan_file}")"

    cat > "${meta_file}" <<EOF
takeover_status=${takeover_status}
doctor_status=${doctor_status}
duration_seconds=$((end_ts - start_ts))
category=${category}
EOF
  )
}

run_blocked_scenario() {
  local scenario_dir="${TMP_DIR}/blocked"
  local repo_dir="${scenario_dir}/repo"
  local meta_file="${scenario_dir}/meta.env"
  local plan_file="${scenario_dir}/plan.json"
  local doctor_file="${scenario_dir}/doctor.json"
  local handover_file="${scenario_dir}/handover.json"

  create_fixture_repo "${scenario_dir}"

  (
    cd "${repo_dir}"

    local takeover_status doctor_status category
    local takeover_log="${scenario_dir}/takeover.stderr"
    local doctor_log="${scenario_dir}/doctor.stderr"

    "${MAW_BIN}" init >/dev/null 2>&1
    "${MAW_BIN}" spawn ws1 --agent claude --issue 10 >/dev/null 2>&1
    "${MAW_BIN}" claim src/auth.ts --workspace ws1 >/dev/null 2>&1
    mkdir -p ".maw-workspaces/ws1/src"
    printf 'dirty change\n' > ".maw-workspaces/ws1/src/auth.ts"

    "${MAW_BIN}" handover --workspace ws1 >/dev/null 2>&1
    "${MAW_BIN}" handover --workspace ws1 \
      --verification-status failed \
      --summary "Blocked by failed verification and external dependencies." \
      --resume-command "bats tests/e2e_test.bats" \
      --risk "Critical production validation gap" \
      --risk-severity critical >/dev/null 2>&1
    "${MAW_BIN}" handover --workspace ws1 --blocked-by-type blocker --blocked-by-desc "Critical blocker" >/dev/null 2>&1
    "${MAW_BIN}" handover --workspace ws1 --blocked-by-type dependency --blocked-by-desc "Dependency update pending" >/dev/null 2>&1
    "${MAW_BIN}" handover --workspace ws1 --blocked-by-type issue --blocked-by-desc "Issue triage pending" >/dev/null 2>&1

    if "${MAW_BIN}" takeover ws1 --format plan > "${plan_file}" 2> "${takeover_log}"; then
      takeover_status=0
    else
      takeover_status=$?
      fail_with_context "blocked scenario: takeover(plan) failed with status ${takeover_status}" "${plan_file}" "${takeover_log}"
    fi
    require_jq "${plan_file}" 'type == "object" and .category == "blocked" and .score == 20 and .workspace == "ws1"' \
      "blocked scenario: unexpected takeover(plan) output" "${takeover_log}"

    if "${MAW_BIN}" doctor --json > "${doctor_file}" 2> "${doctor_log}"; then
      doctor_status=0
    else
      doctor_status=$?
      fail_with_context "blocked scenario: doctor(json) failed with status ${doctor_status}" "${doctor_file}" "${doctor_log}"
    fi
    require_jq "${doctor_file}" 'type == "object" and (.checks | type == "array") and (.summary | type == "object")' \
      "blocked scenario: doctor(json) did not return the expected JSON contract" "${doctor_log}"

    cp ".maw/handovers/ws-ws1.json" "${handover_file}"
    category="$(jq -r '.category // ""' "${plan_file}")"

    cat > "${meta_file}" <<EOF
takeover_status=${takeover_status}
doctor_status=${doctor_status}
duration_seconds=0
category=${category}
EOF
  )
}

run_collision_scenario() {
  local scenario_dir="${TMP_DIR}/collision"
  local repo_dir="${scenario_dir}/repo"
  local meta_file="${scenario_dir}/meta.env"

  create_fixture_repo "${scenario_dir}"

  (
    cd "${repo_dir}"

    local conflict_status rejected

    "${MAW_BIN}" init >/dev/null 2>&1
    "${MAW_BIN}" spawn ws1 --agent claude --issue 10 >/dev/null 2>&1
    "${MAW_BIN}" spawn ws2 --agent codex --issue 10 >/dev/null 2>&1
    "${MAW_BIN}" claim src/auth.ts --workspace ws1 >/dev/null 2>&1

    if "${MAW_BIN}" claim src/auth.ts --workspace ws2 > "${scenario_dir}/claim_conflict.log" 2>&1; then
      conflict_status=0
      rejected=0
    else
      conflict_status=$?
      rejected=1
    fi

    if [[ "${rejected}" -ne 1 ]]; then
      fail_with_context "collision scenario: conflicting claim was expected to be rejected" "" "${scenario_dir}/claim_conflict.log"
    fi

    cat > "${meta_file}" <<EOF
attempts=1
rejected=${rejected}
status=${conflict_status}
EOF
  )
}

run_doctor_failure_scenario() {
  local scenario_dir="${TMP_DIR}/doctor_failure"
  local repo_dir="${scenario_dir}/repo"
  local meta_file="${scenario_dir}/meta.env"
  local doctor_file="${scenario_dir}/doctor.json"

  create_fixture_repo "${scenario_dir}"

  (
    cd "${repo_dir}"

    local doctor_status non_passing actionable
    local doctor_log="${scenario_dir}/doctor.stderr"

    "${MAW_BIN}" init >/dev/null 2>&1
    "${MAW_BIN}" spawn ws1 --agent claude --issue 10 >/dev/null 2>&1
    rm -rf ".maw-workspaces/ws1"
    git worktree prune >/dev/null 2>&1

    if "${MAW_BIN}" doctor --json --exit-code-mode multi > "${doctor_file}" 2> "${doctor_log}"; then
      doctor_status=0
    else
      doctor_status=$?
    fi

    if [[ "${doctor_status}" -ne 1 ]]; then
      fail_with_context "doctor_failure scenario: expected doctor(json multi) to fail with exit 1" "${doctor_file}" "${doctor_log}"
    fi
    require_jq "${doctor_file}" 'type == "object" and (.checks | type == "array") and ([.checks[] | select(.status != "passed")] | length > 0)' \
      "doctor_failure scenario: doctor(json multi) did not emit non-passing checks" "${doctor_log}"

    non_passing="$(jq '[.checks[]? | select(.status != "passed")] | length' "${doctor_file}")"
    actionable="$(jq '[.checks[]? | select(.status != "passed" and (.message | type == "string") and (.message | length > 0) and (.fixable | type == "boolean"))] | length' "${doctor_file}")"

    if [[ "${non_passing}" -eq 0 || "${actionable}" -eq 0 ]]; then
      fail_with_context "doctor_failure scenario: expected at least one actionable non-passing check" "${doctor_file}" "${doctor_log}"
    fi

    cat > "${meta_file}" <<EOF
doctor_status=${doctor_status}
non_passing=${non_passing}
actionable=${actionable}
EOF
  )
}

collect_metrics_json() {
  local ready_meta="${TMP_DIR}/ready/meta.env"
  local caution_meta="${TMP_DIR}/caution/meta.env"
  local blocked_meta="${TMP_DIR}/blocked/meta.env"
  local collision_meta="${TMP_DIR}/collision/meta.env"
  local doctor_failure_meta="${TMP_DIR}/doctor_failure/meta.env"

  local resume_success_numerator=0
  local resume_success_denominator=3
  local ready_takeover_status caution_takeover_status blocked_takeover_status

  ready_takeover_status="$(meta_get "${ready_meta}" "takeover_status")"
  caution_takeover_status="$(meta_get "${caution_meta}" "takeover_status")"
  blocked_takeover_status="$(meta_get "${blocked_meta}" "takeover_status")"

  [[ "${ready_takeover_status}" -eq 0 ]] && resume_success_numerator=$((resume_success_numerator + 1))
  [[ "${caution_takeover_status}" -eq 0 ]] && resume_success_numerator=$((resume_success_numerator + 1))
  [[ "${blocked_takeover_status}" -eq 0 ]] && resume_success_numerator=$((resume_success_numerator + 1))

  local ready_false_positive_numerator=0
  local ready_false_positive_denominator=0
  local ready_category ready_doctor_status ready_verification_status

  ready_category="$(meta_get "${ready_meta}" "category")"
  ready_doctor_status="$(meta_get "${ready_meta}" "doctor_status")"
  ready_verification_status="$(jq -r '.verification_status // ""' "${TMP_DIR}/ready/handover.json")"
  if [[ "${ready_category}" == "ready" ]]; then
    ready_false_positive_denominator=1
    if [[ "${ready_verification_status}" != "passed" || "${ready_doctor_status}" -ne 0 ]]; then
      ready_false_positive_numerator=1
    fi
  fi

  local safe_takeover_total_seconds
  local safe_takeover_denominator=2
  safe_takeover_total_seconds=$(( \
    $(meta_get "${ready_meta}" "duration_seconds") + \
    $(meta_get "${caution_meta}" "duration_seconds") \
  ))

  local collision_numerator collision_denominator
  collision_numerator="$(meta_get "${collision_meta}" "rejected")"
  collision_denominator="$(meta_get "${collision_meta}" "attempts")"

  local doctor_actionability_numerator doctor_actionability_denominator
  doctor_actionability_numerator="$(meta_get "${doctor_failure_meta}" "actionable")"
  doctor_actionability_denominator="$(meta_get "${doctor_failure_meta}" "non_passing")"

  local auto_filled_numerator=0
  local auto_filled_denominator=3
  local handover_file=""
  for handover_file in \
    "${TMP_DIR}/ready/handover.json" \
    "${TMP_DIR}/caution/handover.json" \
    "${TMP_DIR}/blocked/handover.json"; do
    if jq -e '(.summary // "") != "" and ((.evidence_refs // []) | length > 0)' "${handover_file}" >/dev/null; then
      auto_filled_numerator=$((auto_filled_numerator + 1))
    fi
  done

  jq -n \
    --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg note "synthetic proxy, not production telemetry" \
    --arg ready_source "synthetic:ready,caution,blocked" \
    --arg timing_source "synthetic:ready,caution" \
    --arg collision_source "synthetic:collision" \
    --arg doctor_source "synthetic:doctor_failure" \
    --arg auto_fill_source "synthetic:ready,caution,blocked" \
    --arg resume_method "Successful maw takeover --format plan executions across the ready, caution, and blocked scenarios." \
    --arg ready_fp_method "Ready-classified scenarios where verification_status is not passed or doctor --json --exit-code-mode multi is non-zero." \
    --arg timing_method "Average elapsed seconds from the first handover command through takeover(plan) and doctor(json multi) completion." \
    --arg collision_method "Rejected conflicting maw claim attempts before merge in the dedicated collision scenario." \
    --arg doctor_method "Non-passing doctor checks whose message is non-empty and whose fixable field remains boolean." \
    --arg auto_fill_method "Handover bundles with both a non-empty summary and at least one evidence_refs entry." \
    --argjson resume_success_numerator "${resume_success_numerator}" \
    --argjson resume_success_denominator "${resume_success_denominator}" \
    --argjson resume_success_value "$(ratio_value "${resume_success_numerator}" "${resume_success_denominator}")" \
    --argjson ready_false_positive_numerator "${ready_false_positive_numerator}" \
    --argjson ready_false_positive_denominator "${ready_false_positive_denominator}" \
    --argjson ready_false_positive_value "$(ratio_value "${ready_false_positive_numerator}" "${ready_false_positive_denominator}")" \
    --argjson safe_takeover_total_seconds "${safe_takeover_total_seconds}" \
    --argjson safe_takeover_denominator "${safe_takeover_denominator}" \
    --argjson safe_takeover_value "$(average_value "${safe_takeover_total_seconds}" "${safe_takeover_denominator}")" \
    --argjson collision_numerator "${collision_numerator}" \
    --argjson collision_denominator "${collision_denominator}" \
    --argjson collision_value "$(ratio_value "${collision_numerator}" "${collision_denominator}")" \
    --argjson doctor_actionability_numerator "${doctor_actionability_numerator}" \
    --argjson doctor_actionability_denominator "${doctor_actionability_denominator}" \
    --argjson doctor_actionability_value "$(ratio_value "${doctor_actionability_numerator}" "${doctor_actionability_denominator}")" \
    --argjson auto_filled_numerator "${auto_filled_numerator}" \
    --argjson auto_filled_denominator "${auto_filled_denominator}" \
    --argjson auto_filled_value "$(ratio_value "${auto_filled_numerator}" "${auto_filled_denominator}")" \
    '{
      version: 1,
      generated_at: $generated_at,
      mode: "proxy",
      metrics: {
        resume_success_rate: {
          value: $resume_success_value,
          numerator: $resume_success_numerator,
          denominator: $resume_success_denominator,
          unit: "ratio",
          source: $ready_source,
          method: $resume_method
        },
        ready_false_positive_rate: {
          value: $ready_false_positive_value,
          numerator: $ready_false_positive_numerator,
          denominator: $ready_false_positive_denominator,
          unit: "ratio",
          source: $ready_source,
          method: $ready_fp_method
        },
        mean_time_to_safe_takeover_seconds: {
          value: $safe_takeover_value,
          numerator: $safe_takeover_total_seconds,
          denominator: $safe_takeover_denominator,
          unit: "seconds",
          source: $timing_source,
          method: $timing_method
        },
        pre_merge_collision_prevention_rate: {
          value: $collision_value,
          numerator: $collision_numerator,
          denominator: $collision_denominator,
          unit: "ratio",
          source: $collision_source,
          method: $collision_method
        },
        doctor_actionability_rate: {
          value: $doctor_actionability_value,
          numerator: $doctor_actionability_numerator,
          denominator: $doctor_actionability_denominator,
          unit: "ratio",
          source: $doctor_source,
          method: $doctor_method
        },
        auto_filled_handover_ratio: {
          value: $auto_filled_value,
          numerator: $auto_filled_numerator,
          denominator: $auto_filled_denominator,
          unit: "ratio",
          source: $auto_fill_source,
          method: $auto_fill_method
        }
      },
      notes: [
        $note,
        "Scenarios: ready, caution, blocked, collision, doctor_failure"
      ]
    }'
}

write_artifacts() {
  local json_output="$1"
  local json_path="${OUTPUT_DIR}/${OUTPUT_DATE}-phase1-proxy-metrics.json"
  local md_path="${OUTPUT_DIR}/${OUTPUT_DATE}-phase1-proxy-metrics.md"

  mkdir -p "${OUTPUT_DIR}"
  printf '%s\n' "${json_output}" > "${json_path}"
  {
    printf '| metric | value | ratio | source | method | notes |\n'
    printf '| --- | ---: | --- | --- | --- | --- |\n'
    printf '%s\n' "${json_output}" | jq -r '
      .metrics
      | to_entries[]
      | "| \(.key) | \(.value.value) | \(.value.numerator)/\(.value.denominator) | \(.value.source) | \(.value.method) | synthetic proxy, not production telemetry |"
    '
  } > "${md_path}"
}

main() {
  require_tools
  parse_args "$@"

  run_ready_scenario
  run_caution_scenario
  run_blocked_scenario
  run_collision_scenario
  run_doctor_failure_scenario

  local json_output
  json_output="$(collect_metrics_json)"

  if [[ -n "${OUTPUT_DIR}" ]]; then
    write_artifacts "${json_output}"
  fi

  printf '%s\n' "${json_output}"
}

main "$@"
