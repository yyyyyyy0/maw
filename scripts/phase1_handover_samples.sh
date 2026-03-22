#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${REPO_ROOT}/lib/core.sh"
source "${REPO_ROOT}/lib/validate.sh"

OUTPUT_DATE="$(date +"%Y-%m-%d")"
OUTPUT_DIR="${REPO_ROOT}/reports/evaluation"
SOURCE_DIR=""
SOURCE_REF_PREFIX=""

SAMPLE_FILES=(
  "ws-issue10_t2_docs.json"
  "ws-issue10_t3_pr.json"
  "ws-issue10_t6_pr.json"
)

usage() {
  cat <<'EOF'
Usage: phase1_handover_samples.sh [--output-dir <dir>] [--date <YYYY-MM-DD>] [--source-dir <dir>]

Promote operational handover JSON samples into tracked evaluation artifacts.

Options:
  --output-dir <dir>   Directory for generated evaluation artifacts (default: reports/evaluation)
  --date <YYYY-MM-DD>  Override artifact filename date (default: current local date)
  --source-dir <dir>   Directory containing source handover JSON files
  -h, --help           Show this help
EOF
}

require_tools() {
  local tool=""
  for tool in jq cp mkdir mktemp; do
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
      --source-dir)
        [[ $# -ge 2 ]] || {
          echo "--source-dir requires a value" >&2
          exit 1
        }
        SOURCE_DIR="$2"
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

dir_has_all_samples() {
  local dir="$1"
  local sample=""
  for sample in "${SAMPLE_FILES[@]}"; do
    [[ -f "${dir}/${sample}" ]] || return 1
  done
  return 0
}

resolve_source_dir() {
  if [[ -n "${SOURCE_DIR}" ]]; then
    case "${SOURCE_DIR}" in
      /*) ;;
      *) SOURCE_DIR="$(cd "${SOURCE_DIR}" && pwd)" || fail "source dir not found: ${SOURCE_DIR}" ;;
    esac
    [[ -d "${SOURCE_DIR}" ]] || fail "source dir not found: ${SOURCE_DIR}"
    case "${SOURCE_DIR}" in
      "${REPO_ROOT}"/*)
        SOURCE_REF_PREFIX="${SOURCE_DIR#${REPO_ROOT}/}"
        ;;
      *)
        SOURCE_REF_PREFIX="${SOURCE_DIR}"
        ;;
    esac
    return 0
  fi

  local operational_source_dir="${REPO_ROOT}/.maw/handovers"
  if [[ -d "${operational_source_dir}" ]] && dir_has_all_samples "${operational_source_dir}"; then
    SOURCE_DIR="${operational_source_dir}"
    SOURCE_REF_PREFIX=".maw/handovers"
    return 0
  fi

  local tracked_source_dir="${REPO_ROOT}/reports/evaluation/handovers"
  if [[ -d "${tracked_source_dir}" ]] && dir_has_all_samples "${tracked_source_dir}"; then
    SOURCE_DIR="${tracked_source_dir}"
    SOURCE_REF_PREFIX="reports/evaluation/handovers"
    return 0
  fi

  fail "could not locate .maw/handovers from ${REPO_ROOT}"
}

validate_source_handover() {
  local json_file="$1"
  local rel_ref="$2"

  validate_handover_bundle "${json_file}" >/dev/null 2>&1 || fail "invalid handover sample: ${rel_ref}"

  jq -e '
    type == "object" and
    (.version | type == "number" and . == floor and . > 0) and
    (.branch | type == "string") and
    (.branch != "") and
    (.agent | type == "string") and
    (.agent != "") and
    (.state | type == "string") and
    (.state != "") and
    (.summary | type == "string") and
    (.summary != "") and
    (.evidence_refs | type == "array") and
    ((.evidence_refs | length) >= 1) and
    all(.evidence_refs[]; type == "string" and . != "") and
    (.workspace | type == "string") and
    (.workspace != "") and
    (.verification_status | type == "string") and
    (.verification_status != "") and
    (if has("blocked_by") then
      (.blocked_by | type == "array") and
      all(.blocked_by[]; type == "string" or type == "object")
    else true end)
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
    blocked_by: (.blocked_by // [])
  }' "${json_file}"
}

copy_sample_files() {
  local source_dir="$1"
  local target_dir="$2"
  local target_parent_dir
  local staging_dir
  local sample=""

  target_parent_dir="$(dirname "${target_dir}")"
  mkdir -p "${target_parent_dir}"
  staging_dir="$(mktemp -d "${target_parent_dir}/handovers.tmp.XXXXXX")"

  for sample in "${SAMPLE_FILES[@]}"; do
    local source_file="${source_dir}/${sample}"
    local tmp_file="${staging_dir}/${sample}.tmp"
    [[ -f "${source_file}" ]] || fail "missing handover sample: ${source_file}"
    validate_source_handover "${source_file}" "${SOURCE_REF_PREFIX}/${sample}"
    local expected_workspace="${sample#ws-}"
    expected_workspace="${expected_workspace%.json}"
    local actual_workspace
    actual_workspace="$(jq -r '.workspace' "${source_file}")"
    if [[ "${actual_workspace}" != "${expected_workspace}" ]]; then
      rm -rf "${staging_dir}"
      fail "workspace mismatch in ${sample}: expected '${expected_workspace}', got '${actual_workspace}'"
    fi
    project_tracked_handover "${source_file}" > "${tmp_file}"
    mv "${tmp_file}" "${staging_dir}/${sample}"
  done

  mkdir -p "${target_dir}"
  for sample in "${SAMPLE_FILES[@]}"; do
    mv "${staging_dir}/${sample}" "${target_dir}/${sample}"
  done
  rm -rf "${staging_dir}"
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
      jq \
        --arg id "${sample%.json}" \
        --arg workspace "${workspace}" \
        --arg summary "${summary}" \
        --argjson evidence_refs_count "${evidence_refs_count}" \
        --arg verification_status "${verification_status}" \
        --arg source_ref "${SOURCE_REF_PREFIX}/${sample}" \
        '. + [{
          id: $id,
          workspace: $workspace,
          summary: $summary,
          evidence_refs_count: $evidence_refs_count,
          verification_status: $verification_status,
          source_ref: $source_ref
        }]' <<<"${sample_entries}"
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

  resolve_source_dir
  source_dir="${SOURCE_DIR}"
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
