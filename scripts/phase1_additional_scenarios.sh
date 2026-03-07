#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MAW_BIN="${REPO_ROOT}/bin/maw"

OUTPUT_DATE="$(date +"%Y-%m-%d")"
OUTPUT_DIR="${REPO_ROOT}/reports/evaluation"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: phase1_additional_scenarios.sh [--output-dir <dir>] [--date <YYYY-MM-DD>]

Run additional Phase 1 evaluation scenarios and write evidence artifacts.

Options:
  --output-dir <dir>   Directory for JSON/Markdown artifacts (default: reports/evaluation)
  --date <YYYY-MM-DD>  Override artifact filename date (default: current local date)
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

fail_with_context() {
  local message="$1"
  local log_file="${2:-}"

  echo "${message}" >&2
  if [[ -n "${log_file}" && -f "${log_file}" ]]; then
    echo "--- scenario log ---" >&2
    cat "${log_file}" >&2
  fi
  exit 1
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

run_merge_conflict_scenario() {
  local scenario_dir="${TMP_DIR}/merge_conflict"
  local repo_dir="${scenario_dir}/repo"
  local log_file="${scenario_dir}/merge.log"
  local merge_exit_code=0
  local unmerged_entries_count=0
  local conflict_detected="false"
  local passed="false"

  create_fixture_repo "${scenario_dir}"

  (
    cd "${repo_dir}"

    "${MAW_BIN}" init >/dev/null 2>&1
    mkdir -p src
    printf 'shared-line\n' > src/conflict.txt
    git add src/conflict.txt
    git commit -m "add conflict target" >/dev/null 2>&1
    git push origin main >/dev/null 2>&1

    "${MAW_BIN}" spawn ws1 --agent claude --issue 10 >/dev/null 2>&1

    (
      cd ".maw-workspaces/ws1"
      printf 'workspace-line\n' > src/conflict.txt
      git add src/conflict.txt
      git commit -m "workspace conflict change" >/dev/null 2>&1
    )

    printf 'root-line\n' > src/conflict.txt
    git add src/conflict.txt
    git commit -m "root conflict change" >/dev/null 2>&1

    if "${MAW_BIN}" merge ws1 > "${log_file}" 2>&1; then
      merge_exit_code=0
    else
      merge_exit_code=$?
    fi

    unmerged_entries_count="$(git ls-files -u | wc -l | tr -d ' ')"
    if [[ "${merge_exit_code}" -ne 0 && "${unmerged_entries_count}" -gt 0 ]]; then
      conflict_detected="true"
      passed="true"
    fi

    jq -n \
      --arg id "merge_conflict" \
      --argjson passed "${passed}" \
      --arg summary "maw merge fails on conflicting same-line edits and leaves unmerged entries in the root repository." \
      --argjson merge_exit_code "${merge_exit_code}" \
      --argjson unmerged_entries_count "${unmerged_entries_count}" \
      --argjson conflict_detected "${conflict_detected}" \
      '{
        id: $id,
        passed: $passed,
        summary: $summary,
        evidence_refs: [
          "cmd:maw merge ws1",
          "git:git ls-files -u",
          "log:merge_conflict/merge.log"
        ],
        checks: {
          merge_exit_code: $merge_exit_code,
          unmerged_entries_count: $unmerged_entries_count,
          conflict_detected: $conflict_detected
        }
      }'
  )
}

run_ttl_expiry_doctor_fix_scenario() {
  local scenario_dir="${TMP_DIR}/ttl_expiry_doctor_fix"
  local repo_dir="${scenario_dir}/repo"
  local doctor_before_fix_json="${scenario_dir}/doctor_before_fix.json"
  local doctor_before_fix_err="${scenario_dir}/doctor_before_fix.err"
  local fix_log="${scenario_dir}/doctor_fix.log"
  local doctor_json="${scenario_dir}/doctor_after_fix.json"
  local doctor_json_err="${scenario_dir}/doctor_after_fix.err"

  create_fixture_repo "${scenario_dir}"

  (
    cd "${repo_dir}"

    local expired_detected="false"
    local claims_before_fix=0
    local claims_after_fix=0
    local doctor_before_fix_exit_code=0
    local doctor_after_fix_exit_code=0
    local passed="false"

    "${MAW_BIN}" init >/dev/null 2>&1
    mkdir -p src
    : > src/auth.ts
    "${MAW_BIN}" spawn ws1 --agent claude --issue 10 >/dev/null 2>&1
    "${MAW_BIN}" claim src/auth.ts --workspace ws1 --ttl 0 >/dev/null 2>&1
    sleep 1

    if "${MAW_BIN}" doctor --json --exit-code-mode multi > "${doctor_before_fix_json}" 2> "${doctor_before_fix_err}"; then
      doctor_before_fix_exit_code=0
    else
      doctor_before_fix_exit_code=$?
    fi

    if jq -e '
      .categories.stale_claims.status == "warning" and
      ([.checks[] | select(.name == "stale_claims" and .status == "warning" and .fixable == true)] | length) == 1
    ' "${doctor_before_fix_json}" >/dev/null 2>&1; then
      expired_detected="true"
    fi

    claims_before_fix="$(jq '.claims | length' .maw/claims.json)"
    "${MAW_BIN}" doctor --fix > "${fix_log}" 2>&1
    claims_after_fix="$(jq '.claims | length' .maw/claims.json)"

    if "${MAW_BIN}" doctor --json --exit-code-mode multi > "${doctor_json}" 2> "${doctor_json_err}"; then
      doctor_after_fix_exit_code=0
    else
      doctor_after_fix_exit_code=$?
    fi

    if [[ "${doctor_before_fix_exit_code}" -eq 2 && "${expired_detected}" == "true" && "${claims_before_fix}" -gt 0 && "${claims_after_fix}" -eq 0 && "${doctor_after_fix_exit_code}" -eq 0 ]]; then
      passed="true"
    fi

    jq -n \
      --arg id "ttl_expiry_doctor_fix" \
      --argjson passed "${passed}" \
      --arg summary "Expired claims are detected, removed by maw doctor --fix, and followed by a clean doctor --json --exit-code-mode multi run." \
      --argjson expired_detected "${expired_detected}" \
      --argjson claims_before_fix "${claims_before_fix}" \
      --argjson claims_after_fix "${claims_after_fix}" \
      --argjson doctor_before_fix_exit_code "${doctor_before_fix_exit_code}" \
      --argjson doctor_after_fix_exit_code "${doctor_after_fix_exit_code}" \
      '{
        id: $id,
        passed: $passed,
        summary: $summary,
        evidence_refs: [
          "cmd:maw claim src/auth.ts --workspace ws1 --ttl 0",
          "cmd:maw doctor --json --exit-code-mode multi",
          "cmd:maw doctor --fix",
          "log:ttl_expiry_doctor_fix/doctor_before_fix.json",
          "log:ttl_expiry_doctor_fix/doctor_fix.log"
        ],
        checks: {
          expired_detected: $expired_detected,
          claims_before_fix: $claims_before_fix,
          claims_after_fix: $claims_after_fix,
          doctor_before_fix_exit_code: $doctor_before_fix_exit_code,
          doctor_after_fix_exit_code: $doctor_after_fix_exit_code
        }
      }'
  )
}

run_takeover_formats_for_scope() {
  local scope="$1"
  local scenario_dir="$2"
  local repo_dir="${scenario_dir}/${scope}/repo"
  local format_md=0
  local format_json=0
  local format_prompt=0
  local format_plan=0
  local format=""

  create_fixture_repo "${scenario_dir}/${scope}"

  (
    cd "${repo_dir}"

    "${MAW_BIN}" init >/dev/null 2>&1
    "${MAW_BIN}" spawn ws1 --agent claude --issue 10 >/dev/null 2>&1
    "${MAW_BIN}" handover --workspace ws1 --scope "${scope}" >/dev/null 2>&1

    for format in md json prompt plan; do
      if "${MAW_BIN}" takeover ws1 --format "${format}" > "${scenario_dir}/${scope}-${format}.out" 2> "${scenario_dir}/${scope}-${format}.err"; then
        case "${format}" in
          md) format_md=0 ;;
          json) format_json=0 ;;
          prompt) format_prompt=0 ;;
          plan) format_plan=0 ;;
        esac
      else
        case "${format}" in
          md) format_md=$? ;;
          json) format_json=$? ;;
          prompt) format_prompt=$? ;;
          plan) format_plan=$? ;;
        esac
      fi
    done

    jq -n \
      --argjson md "${format_md}" \
      --argjson json "${format_json}" \
      --argjson prompt "${format_prompt}" \
      --argjson plan "${format_plan}" \
      '{
        md: $md,
        json: $json,
        prompt: $prompt,
        plan: $plan
      }'
  )
}

run_takeover_format_matrix_scenario() {
  local scenario_dir="${TMP_DIR}/takeover_format_matrix"
  local full_bundle_json
  local evidence_only_json
  local passed="false"

  mkdir -p "${scenario_dir}"
  full_bundle_json="$(run_takeover_formats_for_scope "full" "${scenario_dir}")"
  evidence_only_json="$(run_takeover_formats_for_scope "evidence" "${scenario_dir}")"

  if jq -n -e '
    ($full.md == 0 and $full.json == 0 and $full.prompt == 0 and $full.plan == 0) and
    ($evidence.md == 0 and $evidence.json != 0 and $evidence.prompt != 0 and $evidence.plan != 0)
  ' \
    --argjson full "${full_bundle_json}" \
    --argjson evidence "${evidence_only_json}" \
    >/dev/null; then
    passed="true"
  fi

  jq -n \
    --arg id "takeover_format_matrix" \
    --argjson passed "${passed}" \
    --arg summary "takeover succeeds for all formats on full bundles, while evidence-only bundles keep md working and fail json/prompt/plan because the JSON sidecar is absent." \
    --argjson full_bundle "${full_bundle_json}" \
    --argjson evidence_only_bundle "${evidence_only_json}" \
    '{
      id: $id,
      passed: $passed,
      summary: $summary,
      evidence_refs: [
        "cmd:maw handover --workspace ws1 --scope full",
        "cmd:maw handover --workspace ws1 --scope evidence",
        "log:takeover_format_matrix/full-*.out",
        "log:takeover_format_matrix/evidence-*.err"
      ],
      checks: {
        full_bundle: $full_bundle,
        evidence_only_bundle: $evidence_only_bundle
      }
    }'
}

build_report_json() {
  local merge_conflict_json
  local ttl_expiry_json
  local format_matrix_json

  merge_conflict_json="$(run_merge_conflict_scenario)"
  ttl_expiry_json="$(run_ttl_expiry_doctor_fix_scenario)"
  format_matrix_json="$(run_takeover_format_matrix_scenario)"

  jq -n \
    --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg note1 "Synthetic evaluation evidence for backlog A-004." \
    --arg note2 "Scenarios are isolated in temporary repositories and summarize current CLI behavior in this workspace checkout." \
    --argjson merge_conflict "${merge_conflict_json}" \
    --argjson ttl_expiry "${ttl_expiry_json}" \
    --argjson format_matrix "${format_matrix_json}" \
    '{
      version: 1,
      generated_at: $generated_at,
      mode: "evaluation",
      scenarios: [
        $merge_conflict,
        $ttl_expiry,
        $format_matrix
      ],
      notes: [$note1, $note2]
    }'
}

write_markdown_report() {
  local json_path="$1"
  local md_path="$2"
  local scenario=""
  local passed=""
  local summary=""
  local key_checks=""

  {
    printf '# Phase 1 Additional Scenarios (%s)\n\n' "${OUTPUT_DATE}"
    printf 'Synthetic evaluation evidence for backlog A-004. This report is not proxy metrics output.\n\n'
    printf '| scenario | passed | key checks | notes |\n'
    printf '| --- | --- | --- | --- |\n'

    while IFS=$'\t' read -r scenario passed key_checks summary; do
      printf '| %s | %s | %s | %s |\n' "${scenario}" "${passed}" "${key_checks}" "${summary}"
    done < <(
      jq -r '
        .scenarios[]
        | [
            .id,
            (if .passed then "yes" else "no" end),
            (
              if .id == "merge_conflict" then
                "merge_exit_code=\(.checks.merge_exit_code), unmerged_entries_count=\(.checks.unmerged_entries_count)"
              elif .id == "ttl_expiry_doctor_fix" then
                "before=\(.checks.doctor_before_fix_exit_code), after=\(.checks.doctor_after_fix_exit_code), claims_after_fix=\(.checks.claims_after_fix)"
              else
                "full.plan=\(.checks.full_bundle.plan), evidence.json=\(.checks.evidence_only_bundle.json)"
              end
            ),
            .summary
          ]
        | @tsv
      ' "${json_path}"
    )

    while IFS= read -r scenario; do
      printf '\n## %s\n\n' "${scenario}"
      jq -r --arg id "${scenario}" '
        .scenarios[]
        | select(.id == $id)
        | "Summary: \(.summary)\n\nPassed: \(.passed)\n\nEvidence refs:\n" +
          (.evidence_refs | map("- " + .) | join("\n")) +
          "\n\nChecks:\n```json\n" +
          (.checks | tojson) +
          "\n```"
      ' "${json_path}"
      printf '\n'
    done < <(jq -r '.scenarios[].id' "${json_path}")
  } > "${md_path}"
}

main() {
  require_tools
  parse_args "$@"
  mkdir -p "${OUTPUT_DIR}"

  local json_output
  local json_path="${OUTPUT_DIR}/${OUTPUT_DATE}-phase1-additional-scenarios.json"
  local md_path="${OUTPUT_DIR}/${OUTPUT_DATE}-phase1-additional-scenarios.md"

  json_output="$(build_report_json)"
  printf '%s\n' "${json_output}" > "${json_path}"
  write_markdown_report "${json_path}" "${md_path}"
  printf '%s\n' "${json_output}"
}

main "$@"
