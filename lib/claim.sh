#!/usr/bin/env bash
# claim.sh - maw claim コマンド

cmd_claim() {
  local target=""
  local workspace=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workspace) workspace="$2"; shift 2 ;;
      -h|--help)
        echo "Usage: maw claim <file|dir> [--workspace <name>]"
        echo ""
        echo "ファイルまたはディレクトリの排他宣言を行います。"
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
        target="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$target" ]]; then
    log_error "claim 対象を指定してください。"
    echo "Usage: maw claim <file|dir> [--workspace <name>]"
    exit 1
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

  local agent
  agent="$(echo "$state" | jq -r --arg name "$workspace" '.workspaces[$name].agent // ""')"

  # パス正規化
  local claim_path
  claim_path="$(normalize_claim_path "$root" "$target")"

  # 排他チェック
  local claims
  claims="$(read_claims "$root")"

  local conflict=""
  conflict="$(echo "$claims" | jq -r --arg path "$claim_path" --arg ws "$workspace" '
    .claims | to_entries[] |
    select(.value.workspace != $ws) |
    # 完全一致
    if .key == $path then
      "完全一致: \(.key) (workspace: \(.value.workspace))"
    # claim 対象がディレクトリで、既存 claim がその配下
    elif ($path | endswith("/")) and (.key | startswith($path)) then
      "ディレクトリ包含: \(.key) (workspace: \(.value.workspace))"
    # 既存 claim がディレクトリで、claim 対象がその配下
    elif (.key | endswith("/")) and ($path | startswith(.key)) then
      "逆包含: \(.key) (workspace: \(.value.workspace))"
    else
      empty
    end
  ' 2>/dev/null)" || conflict=""

  if [[ -n "$conflict" ]]; then
    log_error "排他競合が検出されました:"
    echo "$conflict" | while IFS= read -r line; do
      log_error "  $line"
    done
    exit 1
  fi

  # claim 登録 (同一 WS の再 claim は冪等に更新)
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  claims="$(echo "$claims" | jq \
    --arg path "$claim_path" \
    --arg ws "$workspace" \
    --arg agent "$agent" \
    --arg now "$now" \
    '.claims[$path] = {workspace: $ws, agent: $agent, claimed_at: $now}')"

  write_claims "$root" "$claims"

  log_success "claim 登録: ${claim_path} -> ${workspace}"
}
