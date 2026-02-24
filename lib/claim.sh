#!/usr/bin/env bash
# claim.sh - maw claim コマンド

# shellcheck source=lib/validate.sh
source "${LIB_DIR}/validate.sh"

cmd_claim() {
  local target=""
  local workspace=""
  local ttl=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workspace) workspace="$2"; shift 2 ;;
      --ttl) ttl="$2"; shift 2 ;;
      -h|--help)
        echo "Usage: maw claim <file|dir> [--workspace <name>] [--ttl <minutes>]"
        echo ""
        echo "ファイルまたはディレクトリの排他宣言を行います。"
        echo ""
        echo "Options:"
        echo "  --workspace <name>  ワークスペース名 (省略時は自動検出)"
        echo "  --ttl <minutes>     有効期限 (分単位、省略時は無期限)"
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

  # パスバリデーションと正規化（セキュリティ対策）
  if ! validate_claim_path "$root" "$target"; then
    exit 1
  fi
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

  # TTL から expires_at を計算 (UTC で統一)
  local expires_at="null"
  if [[ -n "$ttl" ]]; then
    # macOS (BSD date): TZ=UTC で UTC として計算
    # GNU date: -d オプションでパース
    if TZ=UTC date -j -v+"${ttl}M" +"%Y-%m-%dT%H:%M:%SZ" &>/dev/null 2>&1; then
      expires_at="\"$(TZ=UTC date -u -j -v+"${ttl}M" +"%Y-%m-%dT%H:%M:%SZ")\""
    elif date -u -d "+${ttl} minutes" +"%Y-%m-%dT%H:%M:%SZ" &>/dev/null 2>&1; then
      expires_at="\"$(date -u -d "+${ttl} minutes" +"%Y-%m-%dT%H:%M:%SZ")\""
    else
      log_warn "--ttl の日時計算に失敗しました。無期限で登録します。"
    fi
  fi

  claims="$(echo "$claims" | jq \
    --arg path "$claim_path" \
    --arg ws "$workspace" \
    --arg agent "$agent" \
    --arg now "$now" \
    --argjson expires "$expires_at" \
    '.claims[$path] = {workspace: $ws, agent: $agent, claimed_at: $now, expires_at: $expires}')"

  write_claims "$root" "$claims"

  local msg="claim 登録: ${claim_path} -> ${workspace}"
  if [[ "$expires_at" != "null" ]]; then
    msg="${msg} (TTL: ${ttl}分)"
  fi
  log_success "$msg"
}
