#!/usr/bin/env bash
# handover.sh - maw handover コマンド

cmd_handover() {
  local workspace=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workspace) workspace="$2"; shift 2 ;;
      -h|--help)
        echo "Usage: maw handover [--workspace <name>]"
        echo ""
        echo "引き継ぎドキュメントを生成します。"
        echo ""
        echo "Options:"
        echo "  --workspace <name>  ワークスペース名 (省略時は自動検出)"
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
  mkdir -p "${root}/${MAW_HANDOVERS_DIR}"

  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

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
      local commits
      commits="$(cd "$ws_path" && git log --oneline "${base_branch}..HEAD" 2>/dev/null)" || commits=""
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
      local changes
      changes="$(cd "$ws_path" && git diff --name-status "${base_branch}..HEAD" 2>/dev/null)" || changes=""
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
      local uncommitted
      uncommitted="$(cd "$ws_path" && git status --short 2>/dev/null)" || uncommitted=""
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

    # Claims
    echo ""
    echo "## Claims"
    echo ""
    local claims
    claims="$(read_claims "$root")"
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
}
