#!/usr/bin/env bash
# unclaim.sh - maw unclaim コマンド

# shellcheck source=lib/validate.sh
source "${LIB_DIR}/validate.sh"

cmd_unclaim() {
  local target=""
  local workspace=""
  local force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workspace) workspace="$2"; shift 2 ;;
      --force)     force=true; shift ;;
      -h|--help)
        echo "Usage: maw unclaim <file|dir> [--workspace <name>] [--force]"
        echo ""
        echo "ファイルまたはディレクトリの排他宣言を解除します。"
        echo ""
        echo "Options:"
        echo "  --workspace <name>  ワークスペース名 (省略時は自動検出)"
        echo "  --force             他ワークスペースの claim も強制解除"
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
    log_error "unclaim 対象を指定してください。"
    echo "Usage: maw unclaim <file|dir> [--workspace <name>] [--force]"
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

  # パスバリデーションと正規化（セキュリティ対策）
  if ! validate_claim_path "$root" "$target"; then
    exit 1
  fi
  local claim_path
  claim_path="$(normalize_claim_path "$root" "$target")"

  # claim 存在チェック
  local claims
  claims="$(read_claims "$root")"

  local owner
  owner="$(echo "$claims" | jq -r --arg path "$claim_path" '.claims[$path].workspace // ""')"

  if [[ -z "$owner" ]]; then
    log_error "claim が見つかりません: ${claim_path}"
    exit 1
  fi

  # 所有者チェック
  if [[ "$owner" != "$workspace" && "$force" == false ]]; then
    log_error "claim は別のワークスペース '${owner}' に属しています。--force で強制解除できます。"
    exit 1
  fi

  # claim 削除
  claims="$(echo "$claims" | jq --arg path "$claim_path" 'del(.claims[$path])')"
  write_claims "$root" "$claims"

  log_success "claim 解除: ${claim_path}"
}
