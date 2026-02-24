#!/usr/bin/env bash
# handover.sh - maw handover コマンド

cmd_handover() {
  local workspace=""
  local scope="full"
  local validate_name=""
  local edit_mode=false
  local next_step=""
  local decision=""
  local risk=""
  local risk_severity="medium"
  local resume_command=""
  local verification_status=""
  local blocked_by=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workspace) workspace="$2"; shift 2 ;;
      --scope)
        scope="$2"
        if [[ "$scope" != "full" && "$scope" != "summary" && "$scope" != "evidence" ]]; then
          log_error "不正な --scope 値: ${scope} (full|summary|evidence)"
          exit 1
        fi
        shift 2
        ;;
      --validate)
        validate_name="$2"
        shift 2
        ;;
      --next-step)
        edit_mode=true
        next_step="$2"
        shift 2
        ;;
      --decision)
        edit_mode=true
        decision="$2"
        shift 2
        ;;
      --risk)
        edit_mode=true
        risk="$2"
        shift 2
        ;;
      --risk-severity)
        risk_severity="$2"
        case "$risk_severity" in
          low|medium|high|critical) ;;
          *)
            log_error "不正な --risk-severity 値: ${risk_severity} (low|medium|high|critical)"
            exit 1
            ;;
        esac
        shift 2
        ;;
      --resume-command)
        edit_mode=true
        resume_command="$2"
        shift 2
        ;;
      --verification-status)
        edit_mode=true
        verification_status="$2"
        case "$verification_status" in
          pending|passed|failed|skipped) ;;
          *)
            log_error "不正な --verification-status 値: ${verification_status} (pending|passed|failed|skipped)"
            exit 1
            ;;
        esac
        shift 2
        ;;
      --blocked-by)
        edit_mode=true
        blocked_by="$2"
        shift 2
        ;;
      -h|--help)
        echo "Usage: maw handover [--workspace <name>] [--scope full|summary|evidence] [--validate <name>] [edit options]"
        echo ""
        echo "引き継ぎドキュメントを生成または検証します。"
        echo ""
        echo "Options:"
        echo "  --workspace <name>         ワークスペース名 (省略時は自動検出)"
        echo "  --scope <mode>             出力スコープ (full|summary|evidence, デフォルト: full)"
        echo "  --validate <name>          handover JSON を検証"
        echo ""
        echo "Edit options (handover JSON を更新):"
        echo "  --next-step <text>         next_steps 配列に追加"
        echo "  --decision <text>          decisions 配列に追加（タイムスタンプ付き）"
        echo "  --risk <text>              risks 配列に追加（--risk-severity で重要度指定）"
        echo "  --risk-severity <level>    リスク重要度 (low|medium|high|critical, デフォルト: medium)"
        echo "  --resume-command <cmd>     resume_commands 配列に追加"
        echo "  --verification-status <s>  verification_status を更新 (pending|passed|failed|skipped)"
        echo "  --blocked-by <text>        blocked_by 配列に追加"
        return 0
        ;;
      -*)
        log_error "不明なオプション: $1"
        exit 1
        ;;
      *)
        log_error "不明な引数: $1"
        exit 1
        ;;
    esac
  done

  local root
  root="$(require_maw_root)"

  # --validate モード
  if [[ -n "$validate_name" ]]; then
    local json_file="${root}/${MAW_HANDOVERS_DIR}/ws-${validate_name}.json"
    if [[ ! -f "$json_file" ]]; then
      log_error "handover JSON が見つかりません: ${json_file}"
      exit 1
    fi
    # shellcheck source=lib/validate.sh
    source "${LIB_DIR}/validate.sh"
    validate_handover_json "$json_file"
    log_success "validation passed"
    return 0
  fi

  # --edit モード（handover JSON を更新）
  if [[ "$edit_mode" == true ]]; then
    cmd_handover_edit "$root" "$workspace" "$next_step" "$decision" "$risk" "$risk_severity" "$resume_command" "$verification_status" "$blocked_by"
    return $?
  fi

  local root
  root="$(require_maw_root)"

  # ワークスペース検出
  if [[ -z "$workspace" ]]; then
    if ! workspace="$(detect_current_workspace "$root")"; then
      log_error "ワークスペースを検出できません。--workspace で指定してください。"
      exit 1
    fi
  fi

  # ワークスペースが state.json に存在するか確認
  local state
  state="$(read_state "$root")"
  if ! echo "$state" | jq -e --arg name "$workspace" '.workspaces[$name]' &>/dev/null; then
    log_error "ワークスペース '${workspace}' が見つかりません。"
    exit 1
  fi

  local ws_info
  ws_info="$(echo "$state" | jq --arg name "$workspace" '.workspaces[$name]')"

  local branch
  branch="$(echo "$ws_info" | jq -r '.branch')"
  local agent
  agent="$(echo "$ws_info" | jq -r '.agent // ""')"
  local issue
  issue="$(echo "$ws_info" | jq -r '.issue // ""')"
  local created
  created="$(echo "$ws_info" | jq -r '.created // ""')"

  local ws_path="${root}/${MAW_WORKSPACES_DIR}/${workspace}"

  # ベースブランチ (メインプロジェクトルートの current_branch)
  local base_branch
  base_branch="$(cd "$root" && current_branch)"

  # handover ファイル生成
  local handover_file="${root}/${MAW_HANDOVERS_DIR}/ws-${workspace}.md"
  local json_file="${root}/${MAW_HANDOVERS_DIR}/ws-${workspace}.json"
  mkdir -p "${root}/${MAW_HANDOVERS_DIR}"

  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # 共通データ収集
  local commits="" changes="" uncommitted="" diff_stat="" diff_raw="" stash_list=""
  if [[ -d "$ws_path" ]]; then
    commits="$(cd "$ws_path" && git log --oneline "${base_branch}..HEAD" 2>/dev/null)" || commits=""
    changes="$(cd "$ws_path" && git diff --name-status "${base_branch}..HEAD" 2>/dev/null)" || changes=""
    uncommitted="$(cd "$ws_path" && git status --short 2>/dev/null)" || uncommitted=""
    diff_stat="$(cd "$ws_path" && git diff --stat "${base_branch}..HEAD" 2>/dev/null)" || diff_stat=""
    diff_raw="$(cd "$ws_path" && git diff "${base_branch}..HEAD" 2>/dev/null)" || diff_raw=""
    stash_list="$(cd "$ws_path" && git stash list 2>/dev/null)" || stash_list=""
  fi

  local claims
  claims="$(read_claims "$root")"

  # --- Markdown 生成 ---
  {
    echo "# Handover: ${workspace}"
    echo ""
    echo "**生成日時**: ${now}"
    echo ""
    echo "## 基本情報"
    echo ""
    echo "| 項目 | 値 |"
    echo "|---|---|"
    echo "| ワークスペース | ${workspace} |"
    echo "| ブランチ | ${branch} |"
    echo "| ベースブランチ | ${base_branch} |"
    echo "| エージェント | ${agent:--} |"
    echo "| Issue | ${issue:--} |"
    echo "| 作成日 | ${created:--} |"

    # コミット履歴
    echo ""
    echo "## コミット履歴"
    echo ""
    if [[ -d "$ws_path" ]]; then
      if [[ -n "$commits" ]]; then
        echo '```'
        echo "$commits"
        echo '```'
      else
        echo "コミットなし (ベースブランチと同一)"
      fi
    else
      echo "ワークスペースディレクトリが見つかりません。"
    fi

    # 変更ファイル
    echo ""
    echo "## 変更ファイル"
    echo ""
    if [[ -d "$ws_path" ]]; then
      if [[ -n "$changes" ]]; then
        echo '```'
        echo "$changes"
        echo '```'
      else
        echo "変更なし"
      fi
    else
      echo "ワークスペースディレクトリが見つかりません。"
    fi

    # 未コミット変更
    echo ""
    echo "## 未コミット変更"
    echo ""
    if [[ -d "$ws_path" ]]; then
      if [[ -n "$uncommitted" ]]; then
        echo '```'
        echo "$uncommitted"
        echo '```'
      else
        echo "なし"
      fi
    else
      echo "ワークスペースディレクトリが見つかりません。"
    fi

    # diff (scope=summary では省略)
    if [[ "$scope" != "summary" ]]; then
      echo ""
      echo "## Diff"
      echo ""
      if [[ -d "$ws_path" ]]; then
        if [[ -n "$diff_stat" ]]; then
          echo '```'
          echo "$diff_stat"
          echo '```'
        else
          echo "差分なし"
        fi
      else
        echo "ワークスペースディレクトリが見つかりません。"
      fi
    fi

    # Claims
    echo ""
    echo "## Claims"
    echo ""
    local ws_claims
    ws_claims="$(echo "$claims" | jq -r --arg ws "$workspace" \
      '.claims | to_entries[] | select(.value.workspace == $ws) | "- \(.key)"')" || ws_claims=""
    if [[ -n "$ws_claims" ]]; then
      echo "$ws_claims"
    else
      echo "排他宣言なし"
    fi

    # 引き継ぎメモ
    echo ""
    echo "## 引き継ぎメモ"
    echo ""
    echo "<!-- ここに引き継ぎ事項を記載してください -->"

  } > "$handover_file"

  log_success "handover 生成: ${handover_file}"

  # --- JSON サイドカー生成 (evidence スコープ以外) ---
  if [[ "$scope" != "evidence" ]]; then
    # state 判定
    local ws_state="clean"
    local porcelain=""
    if [[ -d "$ws_path" ]]; then
      porcelain="$(cd "$ws_path" && git status --porcelain 2>/dev/null)" || porcelain=""
    fi
    if [[ -n "$porcelain" ]]; then
      ws_state="dirty"
    elif [[ -n "$stash_list" ]]; then
      ws_state="stash"
    fi

    # diff (scope=summary では空文字)
    local diff_value=""
    if [[ "$scope" != "summary" ]]; then
      if [[ ${#diff_raw} -gt 4096 ]]; then
        diff_value="${diff_raw:0:4096}"$'\n'"...(truncated)"
      else
        diff_value="$diff_raw"
      fi
    fi

    # log を JSON 配列化
    local log_json="[]"
    if [[ -n "$commits" ]]; then
      log_json="$(echo "$commits" | jq -R '[.,inputs]')"
    fi

    # claims を workspace でフィルタして JSON オブジェクト化
    local claims_json
    claims_json="$(echo "$claims" | jq --arg ws "$workspace" \
      '[.claims | to_entries[] | select(.value.workspace == $ws)] | from_entries')"

    # jq で JSON 生成 (version 2)
    local json
    json="$(jq -n \
      --argjson version 2 \
      --arg workspace "$workspace" \
      --arg branch "$branch" \
      --arg base_branch "$base_branch" \
      --arg agent "$agent" \
      --arg issue "$issue" \
      --arg diff_stat "$diff_stat" \
      --arg diff "$diff_value" \
      --argjson log "$log_json" \
      --argjson claims "$claims_json" \
      --arg state "$ws_state" \
      --argjson decisions "[]" \
      --argjson risks "[]" \
      --argjson blocked_by "[]" \
      --argjson resume_commands "[]" \
      --arg verification_status "pending" \
      --arg generated_at "$now" \
      '{
        version: $version,
        workspace: $workspace,
        branch: $branch,
        base_branch: $base_branch,
        agent: $agent,
        issue: $issue,
        diff_stat: $diff_stat,
        diff: $diff,
        log: $log,
        claims: $claims,
        state: $state,
        next_steps: [],
        decisions: $decisions,
        risks: $risks,
        blocked_by: $blocked_by,
        resume_commands: $resume_commands,
        verification_status: $verification_status,
        generated_at: $generated_at
      }')"

    echo "$json" > "$json_file"
    log_success "handover JSON 生成: ${json_file}"
  fi
}

# handover JSON 編集モード
cmd_handover_edit() {
  local root="$1"
  local workspace="$2"
  local next_step="$3"
  local decision="$4"
  local risk="$5"
  local risk_severity="$6"
  local resume_command="$7"
  local verification_status="$8"
  local blocked_by="$9"

  # ワークスペース検出
  if [[ -z "$workspace" ]]; then
    if ! workspace="$(detect_current_workspace "$root")"; then
      log_error "ワークスペースを検出できません。--workspace で指定してください。"
      exit 1
    fi
  fi

  local json_file="${root}/${MAW_HANDOVERS_DIR}/ws-${workspace}.json"
  if [[ ! -f "$json_file" ]]; then
    log_error "handover JSON が見つかりません: ${json_file}"
    exit 1
  fi

  # JSON を読み込んで更新
  local json_data
  json_data="$(cat "$json_file")"

  local updated=false
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # version チェックと v1→v2 互換性処理
  local version
  version="$(echo "$json_data" | jq -r '.version // 1')"
  if [[ "$version" == "1" ]]; then
    json_data="$(echo "$json_data" | jq '
      .decisions = [] |
      .risks = [] |
      .blocked_by = [] |
      .resume_commands = [] |
      .verification_status = "pending"
    ')"
  fi

  # next_steps に追加
  if [[ -n "$next_step" ]]; then
    json_data="$(echo "$json_data" | jq --arg step "$next_step" '.next_steps += [$step]')"
    log_success "next_step を追加: ${next_step}"
    updated=true
  fi

  # decisions に追加
  if [[ -n "$decision" ]]; then
    json_data="$(echo "$json_data" | jq --arg desc "$decision" --arg ts "$now" \
      '.decisions += [{"description": $desc, "timestamp": $ts}]')"
    log_success "decision を追加: ${decision}"
    updated=true
  fi

  # risks に追加
  if [[ -n "$risk" ]]; then
    json_data="$(echo "$json_data" | jq --arg desc "$risk" --arg sev "$risk_severity" --arg ts "$now" \
      '.risks += [{"description": $desc, "severity": $sev, "timestamp": $ts}]')"
    log_success "risk を追加: ${risk} (severity: ${risk_severity})"
    updated=true
  fi

  # resume_commands に追加
  if [[ -n "$resume_command" ]]; then
    json_data="$(echo "$json_data" | jq --arg cmd "$resume_command" '.resume_commands += [$cmd]')"
    log_success "resume_command を追加: ${resume_command}"
    updated=true
  fi

  # blocked_by に追加
  if [[ -n "$blocked_by" ]]; then
    json_data="$(echo "$json_data" | jq --arg desc "$blocked_by" '.blocked_by += [$desc]')"
    log_success "blocked_by を追加: ${blocked_by}"
    updated=true
  fi

  # verification_status を更新
  if [[ -n "$verification_status" ]]; then
    json_data="$(echo "$json_data" | jq --arg status "$verification_status" '.verification_status = $status')"
    log_success "verification_status を更新: ${verification_status}"
    updated=true
  fi

  if [[ "$updated" == false ]]; then
    log_error "編集オプションが指定されていません。"
    exit 1
  fi

  # 検証
  # shellcheck source=lib/validate.sh
  source "${LIB_DIR}/validate.sh"
  local tmp_file
  tmp_file="$(mktemp)"
  echo "$json_data" > "$tmp_file"
  validate_handover_json "$tmp_file"

  # アトミックに書き戻す
  mv "$tmp_file" "$json_file"
  log_success "handover JSON を更新: ${json_file}"
}
