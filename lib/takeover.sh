#!/usr/bin/env bash
# takeover.sh - maw takeover コマンド

cmd_takeover() {
  local name=""
  local format="prompt"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --format)
        if [[ -z "${2:-}" ]]; then
          log_error "--format には値が必要です (md|json|prompt|plan)"
          exit 1
        fi
        format="$2"
        shift 2
        ;;
      -h|--help)
        echo "Usage: maw takeover [<name>] [--format md|json|prompt|plan]"
        echo ""
        echo "handover bundle を読んでセッション再開プロンプトを出力します。"
        echo ""
        echo "Options:"
        echo "  <name>              ワークスペース名 (省略時は自動検出)"
        echo "  --format <format>   出力形式: prompt (デフォルト), md, json, plan"
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
    md|json|prompt|plan) ;;
    *)
      log_error "不明な format: ${format} (md|json|prompt|plan のいずれかを指定)"
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

  # JSON データを読み取り
  local json_data
  json_data="$(cat "$json_file")"

  # version チェックと v1→v2 互換性処理
  local version
  version="$(echo "$json_data" | jq -r '.version // 1')"

  if [[ "$version" == "1" ]]; then
    # v1 は新規フィールドを補完
    json_data="$(echo "$json_data" | jq '
      .decisions = [] |
      .risks = [] |
      .blocked_by = [] |
      .resume_commands = [] |
      .verification_status = "pending"
    ')"
  fi

  # format=plan の場合は構造化プランを出力
  if [[ "$format" == "plan" ]]; then
    generate_takeover_plan "$json_data"
    return 0
  fi

  # format=prompt の場合（agent 自動判定付き）
  generate_prompt "$json_data" "$name"
}

# takeover plan 出力（JSON形式）
generate_takeover_plan() {
  local json_data="$1"

  local workspace branch verification_status state
  local decisions_count risks_count blockers_count
  local resume_commands_json blockers_json

  workspace="$(echo "$json_data" | jq -r '.workspace')"
  branch="$(echo "$json_data" | jq -r '.branch')"
  verification_status="$(echo "$json_data" | jq -r '.verification_status // "pending"')"
  state="$(echo "$json_data" | jq -r '.state // "clean"')"
  decisions_count="$(echo "$json_data" | jq -r '.decisions | length')"
  risks_count="$(echo "$json_data" | jq -r '.risks | length')"
  blockers_count="$(echo "$json_data" | jq -r '.blocked_by | length')"
  resume_commands_json="$(echo "$json_data" | jq -r '.resume_commands // []')"
  # v2(v3) の blocked_by を正規化（stringはそのまま、objectはdescriptionを抽出）
  blockers_json="$(echo "$json_data" | jq '
    .blocked_by[0:3] // [] |
    map(if type == "string" then . else .description // "Blocker without description" end)
  ')"

  # 重み付けスコアリング
  local verification_score state_score blockers_score risks_score total_score category

  # 1. verification_status (40%)
  case "$verification_status" in
    passed) verification_score=100 ;;
    skipped) verification_score=50 ;;
    pending) verification_score=30 ;;
    failed) verification_score=0 ;;
    *) verification_score=30 ;;
  esac

  # 2. state (20%)
  case "$state" in
    clean) state_score=100 ;;
    stash) state_score=60 ;;
    dirty) state_score=40 ;;
    *) state_score=50 ;;
  esac

  # 3. blockers_count (20%)
  if [[ "$blockers_count" -eq 0 ]]; then
    blockers_score=100
  elif [[ "$blockers_count" -le 2 ]]; then
    blockers_score=50
  else
    blockers_score=0
  fi

  # 4. risks (20%) - 各リスクで減点
  local risk_penalty=0
  if [[ "$risks_count" -gt 0 ]]; then
    while IFS= read -r severity; do
      case "$severity" in
        low) ((risk_penalty += 5)) || true ;;
        medium) ((risk_penalty += 10)) || true ;;
        high) ((risk_penalty += 20)) || true ;;
        critical) ((risk_penalty += 40)) || true ;;
      esac
    done < <(echo "$json_data" | jq -r '.risks[].severity // "medium"')
  fi
  risks_score=$((100 - risk_penalty))
  [[ "$risks_score" -lt 0 ]] && risks_score=0

  # 総合スコア計算（加重平均）
  total_score=$(((verification_score * 40 + state_score * 20 + blockers_score * 20 + risks_score * 20) / 100))

  # カテゴリ判定
  if [[ "$total_score" -ge 80 ]]; then
    category="ready"
  elif [[ "$total_score" -ge 50 ]]; then
    category="caution"
  else
    category="blocked"
  fi

  # priority_actions 生成
  local priority_actions
  priority_actions="$(jq -n '[]')"

  if [[ "$category" == "ready" ]]; then
    priority_actions="$(echo "$priority_actions" | jq '. += [{"action": "start", "description": "作業を開始できます", "priority": "high"}]')"
  elif [[ "$category" == "caution" ]]; then
    priority_actions="$(echo "$priority_actions" | jq '. += [{"action": "review", "description": "注意点を確認してください", "priority": "medium"}]')"
  else
    priority_actions="$(echo "$priority_actions" | jq '. += [{"action": "resolve", "description": "ブロッカーを解決してください", "priority": "high"}]')"
  fi

  if [[ "$verification_status" == "pending" ]]; then
    priority_actions="$(echo "$priority_actions" | jq '. += [{"action": "verify", "description": "テストを実行してください", "priority": "medium"}]')"
  fi

  if [[ "$blockers_count" -gt 0 ]]; then
    priority_actions="$(echo "$priority_actions" | jq '. += [{"action": "unblock", "description": "ブロッカーを解決してください", "priority": "high"}]')"
  fi

  # 出力
  jq -n \
    --arg workspace "$workspace" \
    --arg branch "$branch" \
    --arg verification_status "$verification_status" \
    --arg state "$state" \
    --argjson decisions_count "$decisions_count" \
    --argjson risks_count "$risks_count" \
    --argjson blockers_count "$blockers_count" \
    --argjson score "$total_score" \
    --arg category "$category" \
    --argjson priority_actions "$priority_actions" \
    --argjson resume_commands "$resume_commands_json" \
    --argjson blockers "$blockers_json" \
    '{
      workspace: $workspace,
      branch: $branch,
      verification_status: $verification_status,
      state: $state,
      decisions_count: $decisions_count,
      risks_count: $risks_count,
      blockers_count: $blockers_count,
      blockers: $blockers,
      score: $score,
      category: $category,
      priority_actions: $priority_actions,
      resume_commands: $resume_commands
    }'
}

# agent タイプに応じたプロンプト生成
generate_prompt() {
  local json_data="$1"
  local name="$2"

  local agent
  agent="$(echo "$json_data" | jq -r '.agent // "generic"')"

  case "$agent" in
    claude) generate_claude_prompt "$json_data" "$name" ;;
    codex) generate_codex_prompt "$json_data" "$name" ;;
    *) generate_generic_prompt "$json_data" "$name" ;;
  esac
}

# Claude Code 向けプロンプト
generate_claude_prompt() {
  local json_data="$1"
  local name="$2"

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

# Codex 向けプロンプト
generate_codex_prompt() {
  local json_data="$1"
  local name="$2"

  local branch base_branch
  branch="$(echo "$json_data" | jq -r '.branch')"
  base_branch="$(echo "$json_data" | jq -r '.base_branch')"

  echo "Resuming workspace: ${name}"
  echo "Branch: ${branch} (base: ${base_branch})"
  echo ""
  echo "Please continue the work from where we left off."
}

# 汎用プロンプト
generate_generic_prompt() {
  local json_data="$1"
  local name="$2"

  local branch base_branch
  branch="$(echo "$json_data" | jq -r '.branch')"
  base_branch="$(echo "$json_data" | jq -r '.base_branch')"

  echo "# Resume: ${name}"
  echo ""
  echo "Branch: ${branch}"
  echo "Base branch: ${base_branch}"
  echo ""
  echo "Please review the handover documentation and continue the work."
}
