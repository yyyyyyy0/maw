#!/usr/bin/env bats

setup_file() {
  ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  METRICS_SCRIPT="${ROOT_DIR}/scripts/phase1_metrics.sh"
  METRICS_TMPDIR="$(mktemp -d)"
  METRICS_JSON_FILE="${METRICS_TMPDIR}/phase1-metrics.json"

  "${METRICS_SCRIPT}" > "${METRICS_JSON_FILE}"

  export ROOT_DIR
  export METRICS_SCRIPT
  export METRICS_TMPDIR
  export METRICS_JSON_FILE
}

teardown_file() {
  rm -rf "${METRICS_TMPDIR}"
}

assert_metric_exists() {
  local metric="$1"
  run jq -e --arg metric "${metric}" '.metrics | has($metric)' "${METRICS_JSON_FILE}"
  [ "$status" -eq 0 ]
}

assert_metric_shape() {
  local metric="$1"
  run jq -e --arg metric "${metric}" '.metrics[$metric] | has("value") and has("numerator") and has("denominator") and has("unit") and has("source") and has("method")' "${METRICS_JSON_FILE}"
  [ "$status" -eq 0 ]
}

phase1_metrics_returns_valid_proxy_metrics_json() { # @test
  run jq -e 'type == "object" and .version == 1 and .mode == "proxy" and (.generated_at | type == "string") and (.metrics | type == "object") and (.notes | type == "array")' "${METRICS_JSON_FILE}"
  [ "$status" -eq 0 ]
}

phase1_metrics_emits_all_metric_keys_with_required_shape() { # @test
  assert_metric_exists "resume_success_rate"
  assert_metric_exists "ready_false_positive_rate"
  assert_metric_exists "mean_time_to_safe_takeover_seconds"
  assert_metric_exists "pre_merge_collision_prevention_rate"
  assert_metric_exists "doctor_actionability_rate"
  assert_metric_exists "auto_filled_handover_ratio"

  assert_metric_shape "resume_success_rate"
  assert_metric_shape "ready_false_positive_rate"
  assert_metric_shape "mean_time_to_safe_takeover_seconds"
  assert_metric_shape "pre_merge_collision_prevention_rate"
  assert_metric_shape "doctor_actionability_rate"
  assert_metric_shape "auto_filled_handover_ratio"
}

phase1_metrics_uses_expected_canonical_synthetic_metric_values() { # @test
  run jq -e '.metrics.resume_success_rate.numerator == 3 and .metrics.resume_success_rate.denominator == 3 and .metrics.resume_success_rate.value == 1' "${METRICS_JSON_FILE}"
  [ "$status" -eq 0 ]

  run jq -e '.metrics.ready_false_positive_rate.numerator == 0 and .metrics.ready_false_positive_rate.denominator == 1 and .metrics.ready_false_positive_rate.value == 0' "${METRICS_JSON_FILE}"
  [ "$status" -eq 0 ]

  run jq -e '.metrics.pre_merge_collision_prevention_rate.numerator == 1 and .metrics.pre_merge_collision_prevention_rate.denominator == 1 and .metrics.pre_merge_collision_prevention_rate.value == 1' "${METRICS_JSON_FILE}"
  [ "$status" -eq 0 ]

  run jq -e '.metrics.doctor_actionability_rate.numerator == 1 and .metrics.doctor_actionability_rate.denominator == 1 and .metrics.doctor_actionability_rate.value == 1' "${METRICS_JSON_FILE}"
  [ "$status" -eq 0 ]

  run jq -e '.metrics.auto_filled_handover_ratio.numerator == 2 and .metrics.auto_filled_handover_ratio.denominator == 3' "${METRICS_JSON_FILE}"
  [ "$status" -eq 0 ]

  run jq -e '.metrics.mean_time_to_safe_takeover_seconds.denominator == 2 and (.metrics.mean_time_to_safe_takeover_seconds.value >= 0)' "${METRICS_JSON_FILE}"
  [ "$status" -eq 0 ]
}

phase1_metrics_writes_json_and_markdown_artifacts_when_output_dir_is_provided() { # @test
  local output_dir
  output_dir="$(mktemp -d)"

  run "${METRICS_SCRIPT}" --output-dir "${output_dir}" --date "2026-03-07"
  [ "$status" -eq 0 ]

  [ -f "${output_dir}/2026-03-07-phase1-proxy-metrics.json" ]
  [ -f "${output_dir}/2026-03-07-phase1-proxy-metrics.md" ]

  jq -e '.version == 1 and .mode == "proxy"' "${output_dir}/2026-03-07-phase1-proxy-metrics.json" >/dev/null
  grep -F "synthetic proxy, not production telemetry" "${output_dir}/2026-03-07-phase1-proxy-metrics.md" >/dev/null

  rm -rf "${output_dir}"
}
