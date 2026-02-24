#!/usr/bin/env bash
# handover.sh - maw handover コマンド

cmd_handover() {
  local workspace=""
  local scope="full"

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
      -h|--help)
        echo "Usage: maw handover [--workspace <name>] [--scope full|summary|evidence]"
        echo ""
        echo "引き継ぎドキュメントを生成します。"
        echo ""
        echo "Options:"
        echo "  --workspace <name>  ワークスペース名 (省略時は自動検出)"
        echo "  --scope <mode>      出力スコープ (full|summary|evidence, デフォルト: full)"
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

    # jq で JSON 生成
    local json
    json="$(jq -n \
      --argjson version 1 \
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
        generated_at: $generated_at
      }')"

    echo "$json" > "$json_file"
    log_success "handover JSON 生成: ${json_file}"
  fi
}
