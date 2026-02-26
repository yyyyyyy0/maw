#!/usr/bin/env bash
# migrate.sh - maw migrate コマンド (バージョン移行)

cmd_migrate() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: maw migrate <handover-json-file>"
    echo "       maw migrate handover --to v3 <workspace> [--dry-run|--apply]"
    return 0
  fi

  # サブコマンド: maw migrate handover --to v3 <workspace> [--dry-run|--apply]
  if [[ "${1:-}" == "handover" ]]; then
    shift
    cmd_migrate_handover "$@"
    return $?
  fi

  # 後方互換: maw migrate <handover-json-file> (v1→v2)
  local json_file="${1:-}"

  if [[ -z "$json_file" ]]; then
    log_error "Usage: maw migrate <handover-json-file>"
    log_error "       maw migrate handover --to v3 <workspace> [--dry-run|--apply]"
    exit 1
  fi

  if [[ ! -f "$json_file" ]]; then
    log_error "ファイルが見つかりません: ${json_file}"
    exit 1
  fi

  migrate_handover_v1_to_v2 "$json_file"
}

cmd_migrate_handover() {
  local to_version=""
  local workspace=""
  local dry_run=true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --to)
        to_version="$2"
        shift 2
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      --apply)
        dry_run=false
        shift
        ;;
      -h|--help)
        echo "Usage: maw migrate handover --to v3 <workspace> [--dry-run|--apply]"
        echo ""
        echo "handover bundle をバージョン移行します。"
        echo ""
        echo "Options:"
        echo "  --to v3        v3 形式に移行（v2 文字列 blocked_by → object 形式）"
        echo "  --dry-run      変換プレビューのみ表示（デフォルト）"
        echo "  --apply        実際にファイルを書き換える"
        return 0
        ;;
      -*)
        log_error "不明なオプション: $1"
        exit 1
        ;;
      *)
        workspace="$1"
        shift
        ;;
    esac
  done

  if [[ "$to_version" != "v3" ]]; then
    log_error "--to v3 を指定してください（サポートされているバージョン: v3）"
    exit 1
  fi

  if [[ -z "$workspace" ]]; then
    log_error "Usage: maw migrate handover --to v3 <workspace>"
    exit 1
  fi

  # shellcheck source=lib/validate.sh
  source "${LIB_DIR}/validate.sh"
  validate_workspace_name "$workspace" || exit 1

  local root
  root="$(require_maw_root)"
  local json_file="${root}/${MAW_HANDOVERS_DIR}/ws-${workspace}.json"

  if [[ ! -f "$json_file" ]]; then
    log_error "handover JSON が見つかりません: ${json_file}"
    exit 1
  fi

  migrate_handover_v2_to_v3 "$json_file" "$dry_run"
}

migrate_handover_v1_to_v2() {
  local json_file="$1"

  local version
  version="$(jq -r '.version // 1' "$json_file")"

  [[ "$version" != "1" ]] && {
    log_info "Already at version ${version}, migration not needed."
    return 0
  }

  log_info "Migrating ${json_file} from v1 to v2..."

  local tmp
  tmp="$(mktemp)"

  jq '
    .version = 2 |
    .decisions = [] |
    .risks = [] |
    .blocked_by = [] |
    .resume_commands = [] |
    .verification_status = "pending"
  ' "$json_file" > "$tmp" && mv "$tmp" "$json_file"

  log_success "Migration complete"
}

migrate_handover_v2_to_v3() {
  local json_file="$1"
  local dry_run="${2:-true}"

  local version
  version="$(jq -r '.version // 1' "$json_file")"

  if [[ "$version" -ge 3 ]]; then
    log_info "Already at version ${version}, v3 migration not needed."
    return 0
  fi

  # id 生成（既存ファイルに id がない場合の補完用）
  local ws_name ts id
  ws_name="$(jq -r '.workspace // "unknown"' "$json_file")"
  ts="$(jq -r '.generated_at // ""' "$json_file")"
  if command -v sha256sum &>/dev/null; then
    id="$(echo -n "${ws_name}:${ts}" | sha256sum | cut -c1-16)"
  elif command -v md5sum &>/dev/null; then
    id="$(echo -n "${ws_name}:${ts}" | md5sum | cut -c1-16)"
  else
    id="$(echo -n "${ws_name}:${ts}" | md5 -q | cut -c1-16)"
  fi

  # v2 文字列 blocked_by → v3 object 形式に変換
  # id/summary/evidence_refs を補完
  local converted
  converted="$(jq \
    --arg id "$id" \
    '
    .version = 3 |
    .blocked_by = [
      .blocked_by[] |
      if type == "string" then
        {"type": "blocker", "description": ., "resolved": false}
      else
        .
      end
    ] |
    if (.id == null or .id == "") then .id = $id else . end |
    if .summary == null then .summary = "" else . end |
    if .evidence_refs == null then .evidence_refs = [] else . end
  ' "$json_file")"

  if [[ "$dry_run" == true ]]; then
    log_info "Dry-run: ${json_file} の変換プレビュー（blocked_by のみ表示）"
    echo "$converted" | jq '.blocked_by'
    log_info "--apply を付けて実行することで変換を適用します"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  echo "$converted" > "$tmp" && mv "$tmp" "$json_file"
  log_success "Migration complete: ${json_file} (v2 → v3)"
}
