#!/usr/bin/env bash
# takeover.sh - maw takeover コマンド

cmd_takeover() {
  local name=""
  local format="prompt"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --format)
        if [[ -z "${2:-}" ]]; then
          log_error "--format には値が必要です (md|json|prompt)"
          exit 1
        fi
        format="$2"
        shift 2
        ;;
      -h|--help)
        echo "Usage: maw takeover [<name>] [--format md|json|prompt]"
        echo ""
        echo "handover bundle を読んでセッション再開プロンプトを出力します。"
        echo ""
        echo "Options:"
        echo "  <name>              ワークスペース名 (省略時は自動検出)"
        echo "  --format <format>   出力形式: prompt (デフォルト), md, json"
        return 0
        ;;
      -*)
        log_error "不明なオプション: $1"
        exit 1
        ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"
          shift
        else
          log_error "不明な引数: $1"
          exit 1
        fi
        ;;
    esac
  done

  # format のバリデーション
  case "$format" in
    md|json|prompt) ;;
    *)
      log_error "不明な format: ${format} (md|json|prompt のいずれかを指定)"
      exit 1
      ;;
  esac

  local root
  root="$(require_maw_root)"

  # ワークスペース名の検出
  if [[ -z "$name" ]]; then
    if ! name="$(detect_current_workspace "$root")"; then
      log_error "ワークスペースを検出できません。名前を指定してください。"
      exit 1
    fi
  fi

  local json_file="${root}/${MAW_HANDOVERS_DIR}/ws-${name}.json"

  # format=md の場合は .md ファイルを出力
  if [[ "$format" == "md" ]]; then
    local md_file="${root}/${MAW_HANDOVERS_DIR}/ws-${name}.md"
    if [[ ! -f "$md_file" ]]; then
      log_error "handover Markdown が見つかりません: ${md_file}"
      exit 1
    fi
    cat "$md_file"
    return 0
  fi

  # JSON ファイルの存在チェック
  if [[ ! -f "$json_file" ]]; then
    log_error "handover JSON が見つかりません: ${json_file}"
    exit 1
  fi

  # format=json の場合は JSON をそのまま出力
  if [[ "$format" == "json" ]]; then
    jq . "$json_file"
    return 0
  fi

  # format=prompt の場合
  local json_data
  json_data="$(cat "$json_file")"

  local branch base_branch state generated_at
  branch="$(echo "$json_data" | jq -r '.branch')"
  base_branch="$(echo "$json_data" | jq -r '.base_branch')"
  state="$(echo "$json_data" | jq -r '.state')"
  generated_at="$(echo "$json_data" | jq -r '.generated_at')"

  echo "# Resume: ${name}"
  echo ""
  echo "You are resuming work on workspace **${name}** (branch: \`${branch}\`)."
  echo "Base branch: \`${base_branch}\`"
  echo "State: ${state}"
  echo "Generated: ${generated_at}"

  # What was done
  echo ""
  echo "## What was done"
  local log_entries
  log_entries="$(echo "$json_data" | jq -r '.log[]' 2>/dev/null)" || log_entries=""
  if [[ -n "$log_entries" ]]; then
    while IFS= read -r line; do
      echo "- ${line}"
    done <<< "$log_entries"
  else
    echo "(no log entries)"
  fi

  # Changed files (stat)
  echo ""
  echo "## Changed files (stat)"
  local diff_stat
  diff_stat="$(echo "$json_data" | jq -r '.diff_stat' 2>/dev/null)" || diff_stat=""
  if [[ -n "$diff_stat" && "$diff_stat" != "null" && "$diff_stat" != "" ]]; then
    echo "$diff_stat"
  else
    echo "No changes"
  fi

  # Active claims
  echo ""
  echo "## Active claims"
  local claims_output
  claims_output="$(echo "$json_data" | jq -r '
    .claims | to_entries[] |
    "- \(.key) (agent: \(.value.agent // "-"))"
  ' 2>/dev/null)" || claims_output=""
  if [[ -n "$claims_output" ]]; then
    echo "$claims_output"
  else
    echo "None"
  fi

  # Next steps
  echo ""
  echo "## Next steps"
  local next_steps
  next_steps="$(echo "$json_data" | jq -r '.next_steps[]' 2>/dev/null)" || next_steps=""
  if [[ -n "$next_steps" ]]; then
    while IFS= read -r step; do
      echo "- ${step}"
    done <<< "$next_steps"
  else
    echo "(none recorded)"
  fi
}
