#!/usr/bin/env bash
# status.sh - maw status コマンド

cmd_status() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        echo "Usage: maw status"
        echo ""
        echo "ワークスペース状況とファイル排他情報を表示します。"
        return 0
        ;;
      *)
        log_error "不明なオプション: $1"
        exit 1
        ;;
    esac
  done

  local root
  root="$(require_maw_root)"

  local state
  state="$(read_state "$root")"

  # 現在のワークスペースを検出
  local current_ws=""
  current_ws="$(detect_current_workspace "$root" 2>/dev/null)" || true

  # === ワークスペース一覧 ===
  echo "=== Workspaces ==="

  local ws_count
  ws_count="$(echo "$state" | jq '.workspaces | length')"

  if [[ "$ws_count" -eq 0 ]]; then
    log_info "ワークスペースがありません。"
  else
    printf "  %-2s %-16s %-30s %-10s %-8s %s\n" "" "NAME" "BRANCH" "AGENT" "ISSUE" "CREATED"
    echo "  ------------------------------------------------------------------------------------------------"

    echo "$state" | jq -r '.workspaces | to_entries[] | [.key, .value.branch, .value.agent, .value.issue, .value.created] | @tsv' | \
    while IFS=$'\t' read -r name branch agent issue created; do
      local marker="  "
      if [[ "$name" == "$current_ws" ]]; then
        marker="->"
      fi
      agent="${agent:--}"
      issue="${issue:--}"
      local date_str="${created:0:10}"
      printf "  %-2s %-16s %-30s %-10s %-8s %s\n" "$marker" "$name" "$branch" "$agent" "$issue" "$date_str"
    done
  fi

  # === ファイル排他 (Claims) ===
  echo ""
  echo "=== Claims ==="

  local claims
  claims="$(read_claims "$root")"

  local claims_count
  claims_count="$(echo "$claims" | jq '.claims | length')"

  if [[ "$claims_count" -eq 0 ]]; then
    log_info "排他宣言はありません。"
  else
    printf "  %-30s %-16s %-10s %-10s %s\n" "FILE" "WORKSPACE" "AGENT" "CLAIMED" "EXPIRES"
    echo "  --------------------------------------------------------------------------------------"

    echo "$claims" | jq -r '.claims | to_entries[] | [.key, .value.workspace, .value.agent, .value.claimed_at, (.value.expires_at // "")] | @tsv' | \
    while IFS=$'\t' read -r file ws agent claimed expires_at; do
      agent="${agent:--}"
      local date_str="${claimed:0:10}"
      local exp_str="-"
      if [[ -n "$expires_at" && "$expires_at" != "null" ]]; then
        exp_str="${expires_at:0:16}"
      fi
      if [[ -n "$expires_at" && "$expires_at" != "null" ]] && is_claim_expired "$expires_at"; then
        # 期限切れ: 赤色
        printf "  \033[31m%-30s %-16s %-10s %-10s %s [EXPIRED]\033[0m\n" "$file" "$ws" "$agent" "$date_str" "$exp_str"
      elif [[ -n "$expires_at" && "$expires_at" != "null" ]]; then
        # TTL あり: 黄色
        printf "  \033[33m%-30s %-16s %-10s %-10s %s\033[0m\n" "$file" "$ws" "$agent" "$date_str" "$exp_str"
      else
        printf "  %-30s %-16s %-10s %-10s %s\n" "$file" "$ws" "$agent" "$date_str" "$exp_str"
      fi
    done
  fi
}
