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
  local id summary evidence_refs_json

  workspace="$(echo "$json_data" | jq -r '.workspace')"
  branch="$(echo "$json_data" | jq -r '.branch')"
  verification_status="$(echo "$json_data" | jq -r '.verification_status // "pending"')"
  state="$(echo "$json_data" | jq -r '.state // "clean"')"
  decisions_count="$(echo "$json_data" | jq -r '.decisions | length')"
  risks_count="$(echo "$json_data" | jq -r '.risks | length')"
  blockers_count="$(echo "$json_data" | jq -r '.blocked_by | length')"
  resume_commands_json="$(echo "$json_data" | jq -r '.resume_commands // []')"
  id="$(echo "$json_data" | jq -r '.id // ""')"
  summary="$(echo "$json_data" | jq -r '.summary // ""')"
  evidence_refs_json="$(echo "$json_data" | jq '.evidence_refs // []')"
  # v2(v3) の blocked_by を正規化（stringはそのまま、objectはdescriptionを抽出）
  blockers_json="$(echo "$json_data" | jq '
    .blocked_by[0:3] // [] |
    map(
      if type == "string" then .
      elif type == "object" then (.description // "[invalid blocker object]")
      else "[invalid blocker entry]"
      end
    )
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

  # priority_actions 生成（priority_level 付き: 1=最優先, 2=次, 3=その後）
  local priority_actions
  priority_actions="$(jq -n '[]')"

  # Priority Level 1: verification_status = failed
  if [[ "$verification_status" == "failed" ]]; then
    local verify_cmds
    verify_cmds="$(echo "$json_data" | jq '.resume_commands // []')"
    priority_actions="$(echo "$priority_actions" | jq \
      --argjson cmds "$verify_cmds" \
      '. += [{"priority_level": 1, "action": "verify", "description": "テストが失敗しています。resume_commands を実行して確認してください", "commands": $cmds, "priority": "high"}]')"
  fi

  # Priority Level 1: type=blocker（最も緊急度の高いブロッカータイプ）
  while IFS= read -r entry; do
    [[ -z "$entry" || "$entry" == "null" ]] && continue
    local bl_desc bl_owner bl_desc_full
    bl_desc="$(echo "$entry" | jq -r '.description // "不明なブロッカー"')"
    bl_owner="$(echo "$entry" | jq -r '.owner // ""')"
    if [[ -n "$bl_owner" ]]; then
      bl_desc_full="ブロッカーのオーナー ${bl_owner} に連絡して解消してください: ${bl_desc}"
    else
      bl_desc_full="ブロッカーを解消してください: ${bl_desc}"
    fi
    priority_actions="$(echo "$priority_actions" | jq \
      --arg desc "$bl_desc_full" \
      '. += [{"priority_level": 1, "action": "unblock", "description": $desc, "blocker_type": "blocker", "priority": "high"}]')"
  done < <(echo "$json_data" | jq -c '.blocked_by[] | select(type == "object" and .type == "blocker" and (.resolved // false) == false)' 2>/dev/null)

  # Priority Level 2: verification_status = pending
  if [[ "$verification_status" == "pending" ]]; then
    local verify_cmds2
    verify_cmds2="$(echo "$json_data" | jq '.resume_commands // []')"
    priority_actions="$(echo "$priority_actions" | jq \
      --argjson cmds "$verify_cmds2" \
      '. += [{"priority_level": 2, "action": "verify", "description": "テストを実行してください", "commands": $cmds, "priority": "medium"}]')"
  fi

  # Priority Level 2: type=dependency または type=issue（中程度のブロッカータイプ）
  while IFS= read -r entry; do
    [[ -z "$entry" || "$entry" == "null" ]] && continue
    local p2_type p2_desc p2_desc_full
    p2_type="$(echo "$entry" | jq -r '.type')"
    p2_desc="$(echo "$entry" | jq -r '.description // "不明なブロッカー"')"
    case "$p2_type" in
      dependency) p2_desc_full="依存先 PR/タスクの状況を確認してください: ${p2_desc}" ;;
      issue)      p2_desc_full="Issue を参照して解消方法を確認してください: ${p2_desc}" ;;
      *)          p2_desc_full="ブロッカーを確認してください: ${p2_desc}" ;;
    esac
    priority_actions="$(echo "$priority_actions" | jq \
      --arg desc "$p2_desc_full" \
      --arg btype "$p2_type" \
      '. += [{"priority_level": 2, "action": "unblock", "description": $desc, "blocker_type": $btype, "priority": "medium"}]')"
  done < <(echo "$json_data" | jq -c '.blocked_by[] | select(type == "object" and (.type == "dependency" or .type == "issue") and (.resolved // false) == false)' 2>/dev/null)

  # Priority Level 2: v2 文字列ブロッカー（後方互換）
  while IFS= read -r blocker_str; do
    [[ -z "$blocker_str" ]] && continue
    priority_actions="$(echo "$priority_actions" | jq \
      --arg desc "ブロッカーを確認してください: ${blocker_str}" \
      '. += [{"priority_level": 2, "action": "unblock", "description": $desc, "blocker_type": "unknown", "priority": "medium"}]')"
  done < <(echo "$json_data" | jq -r '.blocked_by[] | select(type == "string")' 2>/dev/null)

  # Priority Level 3: カテゴリベースのアクション
  case "$category" in
    ready)
      priority_actions="$(echo "$priority_actions" | jq \
        '. += [{"priority_level": 3, "action": "start", "description": "作業を開始できます", "priority": "low"}]')"
      ;;
    caution)
      priority_actions="$(echo "$priority_actions" | jq \
        '. += [{"priority_level": 3, "action": "review", "description": "注意点を確認してください", "priority": "low"}]')"
      ;;
    blocked)
      # Priority Level 1 のアクションがなければ汎用 resolve を追加
      local p1_count_check
      p1_count_check="$(echo "$priority_actions" | jq '[.[] | select(.priority_level == 1)] | length')"
      if [[ "$p1_count_check" -eq 0 ]]; then
        priority_actions="$(echo "$priority_actions" | jq \
          '. += [{"priority_level": 1, "action": "resolve", "description": "ブロッカーを解決してください", "priority": "high"}]')"
      fi
      ;;
  esac

  # Priority Level 3: next_steps をアクションとして追加
  while IFS= read -r step; do
    [[ -z "$step" ]] && continue
    priority_actions="$(echo "$priority_actions" | jq \
      --arg desc "$step" \
      '. += [{"priority_level": 3, "action": "next_step", "description": $desc, "priority": "low"}]')"
  done < <(echo "$json_data" | jq -r '.next_steps[] // empty' 2>/dev/null)

  # 出力
  jq -n \
    --arg id "$id" \
    --arg summary "$summary" \
    --argjson evidence_refs "$evidence_refs_json" \
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
      id: $id,
      summary: $summary,
      evidence_refs: $evidence_refs,
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

  local branch base_branch state generated_at summary
  branch="$(echo "$json_data" | jq -r '.branch')"
  base_branch="$(echo "$json_data" | jq -r '.base_branch')"
  state="$(echo "$json_data" | jq -r '.state')"
  generated_at="$(echo "$json_data" | jq -r '.generated_at')"
  summary="$(echo "$json_data" | jq -r '.summary // ""')"

  echo "# Resume: ${name}"
  echo ""
  echo "You are resuming work on workspace **${name}** (branch: \`${branch}\`)."
  echo "Base branch: \`${base_branch}\`"
  echo "State: ${state}"
  echo "Generated: ${generated_at}"

  # Summary セクション（summary が非空の場合のみ出力）
  if [[ -n "$summary" ]]; then
    echo ""
    echo "## Summary"
    echo "${summary}"
  fi

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
