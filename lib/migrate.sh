#!/usr/bin/env bash
# migrate.sh - maw migrate コマンド (v1 → v2 移行)

cmd_migrate() {
  local json_file="$1"

  if [[ -z "$json_file" ]]; then
    log_error "Usage: maw migrate <handover-json-file>"
    exit 1
  fi

  if [[ ! -f "$json_file" ]]; then
    log_error "ファイルが見つかりません: ${json_file}"
    exit 1
  fi

  migrate_handover_v1_to_v2 "$json_file"
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
