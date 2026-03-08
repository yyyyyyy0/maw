#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTPUT_DATE="$(date +"%Y-%m-%d")"
OUTPUT_DIR="${REPO_ROOT}/reports/evaluation"

SAMPLE_FILES=(
  "ws-issue10_t2_docs.json"
  "ws-issue10_t3_pr.json"
  "ws-issue10_t6_pr.json"
)

usage() {
  cat <<'EOF'
Usage: phase1_handover_samples.sh [--output-dir <dir>] [--date <YYYY-MM-DD>]

Promote operational handover JSON samples into tracked evaluation artifacts.

Options:
  --output-dir <dir>   Directory for generated evaluation artifacts (default: reports/evaluation)
  --date <YYYY-MM-DD>  Override artifact filename date (default: current local date)
  -h, --help           Show this help
EOF
}

require_tools() {
  local tool=""
  for tool in jq cp mkdir; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      echo "missing required tool: ${tool}" >&2
      exit 1
    fi
  done
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

fail() {
  echo "$1" >&2
  exit 1
}

find_handover_source_dir() {
  local candidate="${REPO_ROOT}"

  while [[ "${candidate}" != "/" ]]; do
    if [[ -d "${candidate}/.maw/handovers" ]]; then
      printf '%s\n' "${candidate}/.maw/handovers"
      return 0
    fi
    candidate="$(dirname "${candidate}")"
  done

  fail "could not locate .maw/handovers from ${REPO_ROOT}"
}

validate_source_handover() {
  local json_file="$1"
  local rel_ref="$2"

  jq -e '
    type == "object" and
    (.summary | type == "string") and
    (.summary != "") and
    (.evidence_refs | type == "array") and
    ((.evidence_refs | length) >= 1) and
    (.workspace | type == "string") and
    (.workspace != "") and
    (.verification_status | type == "string")
  ' "${json_file}" >/dev/null 2>&1 || fail "invalid handover sample: ${rel_ref}"
}

project_tracked_handover() {
  local json_file="$1"

  jq '{
    version,
    workspace,
    branch,
    agent,
    state,
    summary,
    evidence_refs,
    verification_status,
    blocked_by
  }' "${json_file}"
}

copy_sample_files() {
  local source_dir="$1"
  local target_dir="$2"
  local sample=""

  mkdir -p "${target_dir}"

  for sample in "${SAMPLE_FILES[@]}"; do
    local source_file="${source_dir}/${sample}"
    [[ -f "${source_file}" ]] || fail "missing handover sample: ${source_file}"
    validate_source_handover "${source_file}" ".maw/handovers/${sample}"
    project_tracked_handover "${source_file}" > "${target_dir}/${sample}"
  done
}

build_summary_json() {
  local handover_dir="$1"
  local sample_entries="[]"
  local sample=""

  for sample in "${SAMPLE_FILES[@]}"; do
    local tracked_file="${handover_dir}/${sample}"
    local workspace
    local summary
    local evidence_refs_count
    local verification_status

    workspace="$(jq -r '.workspace' "${tracked_file}")"
    summary="$(jq -r '.summary' "${tracked_file}")"
    evidence_refs_count="$(jq '.evidence_refs | length' "${tracked_file}")"
    verification_status="$(jq -r '.verification_status' "${tracked_file}")"

    sample_entries="$(
      jq -n \
        --arg id "${sample%.json}" \
        --arg workspace "${workspace}" \
        --arg summary "${summary}" \
        --argjson evidence_refs_count "${evidence_refs_count}" \
        --arg verification_status "${verification_status}" \
        --arg source_ref ".maw/handovers/${sample}" \
        --argjson current "${sample_entries}" \
        '$current + [{
          id: $id,
          workspace: $workspace,
          summary: $summary,
          evidence_refs_count: $evidence_refs_count,
          verification_status: $verification_status,
          source_ref: $source_ref
        }]' \
        
    )"
  done

  jq -n \
    --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg note1 "Operationally derived handover samples promoted into tracked evaluation artifacts." \
    --arg note2 "Tracked samples are stable projections with non-empty summary and at least one evidence_refs entry." \
    --argjson samples "${sample_entries}" \
    '{
      version: 1,
      generated_at: $generated_at,
      mode: "handover_samples",
      samples: $samples,
      notes: [$note1, $note2]
    }'
}

write_markdown_report() {
  local summary_json="$1"
  local handover_dir="$2"
  local md_path="$3"
  local sample=""

  {
    printf '# Handover Samples (%s)\n\n' "${OUTPUT_DATE}"
    printf 'Operationally derived handover samples promoted into tracked evaluation artifacts.\n'
    printf 'Tracked copies intentionally exclude volatile fields such as claims, raw logs, and raw diffs.\n\n'
    printf '| sample | workspace | verification_status | evidence_refs | notes |\n'
    printf '| --- | --- | --- | ---: | --- |\n'

    jq -r '
      .samples[]
      | "| \(.id) | \(.workspace) | \(.verification_status) | \(.evidence_refs_count) | summary/evidence_refs present |"
    ' <<<"${summary_json}"

    for sample in "${SAMPLE_FILES[@]}"; do
      local tracked_file="${handover_dir}/${sample}"
      printf '\n## %s\n\n' "${sample%.json}"
      jq -r '
        "Workspace: \(.workspace)\n\nSummary: \(.summary)\n\nEvidence refs:\n" +
        (.evidence_refs | map("- " + .) | join("\n")) +
        "\n\nVerification status: \(.verification_status)"
      ' "${tracked_file}"
      printf '\n'
    done
  } > "${md_path}"
}

main() {
  require_tools
  parse_args "$@"

  local source_dir
  local handover_output_dir
  local summary_json
  local summary_json_path
  local summary_md_path

  source_dir="$(find_handover_source_dir)"
  handover_output_dir="${OUTPUT_DIR}/handovers"
  summary_json_path="${OUTPUT_DIR}/${OUTPUT_DATE}-handover-samples.json"
  summary_md_path="${OUTPUT_DIR}/${OUTPUT_DATE}-handover-samples.md"

  mkdir -p "${OUTPUT_DIR}"
  copy_sample_files "${source_dir}" "${handover_output_dir}"

  summary_json="$(build_summary_json "${handover_output_dir}")"
  printf '%s\n' "${summary_json}" > "${summary_json_path}"
  write_markdown_report "${summary_json}" "${handover_output_dir}" "${summary_md_path}"

  printf '%s\n' "${summary_json}"
}

main "$@"
