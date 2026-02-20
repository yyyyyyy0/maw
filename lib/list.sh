#!/usr/bin/env bash
# list.sh - maw list コマンド

cmd_list() {
  local root
  root="$(require_maw_root)"

  local state
  state="$(read_state "$root")"

  local count
  count="$(echo "$state" | jq '.workspaces | length')"

  if [[ "$count" -eq 0 ]]; then
    log_info "ワークスペースがありません。'maw spawn <name>' で作成してください。"
    return 0
  fi

  # ヘッダー
  printf "\033[1m%-16s %-30s %-10s %-8s %s\033[0m\n" \
    "NAME" "BRANCH" "AGENT" "ISSUE" "CREATED"
  printf "%s\n" "$(printf '%.0s-' {1..90})"

  # 各ワークスペースを表示
  echo "$state" | jq -r '.workspaces | to_entries[] | [.key, .value.branch, (if .value.agent == "" or .value.agent == null then "-" else .value.agent end), (if .value.issue == "" or .value.issue == null then "-" else .value.issue end), .value.created] | @tsv' | \
  while IFS=$'\t' read -r name branch agent issue created; do
    # 日付を短縮表示
    local short_date="${created:0:10}"

    # worktree の存在確認
    local ws_path="${root}/${MAW_WORKSPACES_DIR}/${name}"
    local status_icon
    if [[ -d "$ws_path" ]]; then
      status_icon=""
    else
      status_icon=" (missing)"
    fi

    printf "%-16s %-30s %-10s %-8s %s%s\n" \
      "$name" "$branch" "${agent:--}" "${issue:--}" "$short_date" "$status_icon"
  done
}
