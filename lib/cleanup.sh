#!/usr/bin/env bash
# cleanup.sh - maw cleanup コマンド

cmd_cleanup() {
  local target=""
  local all=false
  local merged=false
  local dry_run=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)     all=true; shift ;;
      --merged)  merged=true; shift ;;
      --dry-run) dry_run=true; shift ;;
      -h|--help)
        echo "Usage: maw cleanup [<name>|--all|--merged] [--dry-run]"
        echo ""
        echo "Options:"
        echo "  <name>      特定のワークスペースを削除"
        echo "  --all       全ワークスペースを削除"
        echo "  --merged    マージ済みブランチのワークスペースのみ削除"
        echo "  --dry-run   何が削除されるか表示のみ"
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

  local root
  root="$(require_maw_root)"

  local state
  state="$(read_state "$root")"

  # 削除対象の決定
  local targets=()

  if [[ -n "$target" ]]; then
    # 特定ワークスペース
    if echo "$state" | jq -e --arg name "$target" '.workspaces[$name]' &>/dev/null; then
      targets+=("$target")
    else
      log_error "ワークスペース '${target}' が見つかりません。"
      exit 1
    fi
  elif [[ "$all" == true ]]; then
    # 全ワークスペース
    while IFS= read -r name; do
      targets+=("$name")
    done < <(echo "$state" | jq -r '.workspaces | keys[]')
  elif [[ "$merged" == true ]]; then
    # マージ済みのみ
    local base_branch
    base_branch="$(cd "$root" && current_branch)"

    while IFS= read -r name; do
      local branch
      branch="$(echo "$state" | jq -r --arg name "$name" '.workspaces[$name].branch')"
      if (cd "$root" && is_branch_merged "$branch" "$base_branch"); then
        targets+=("$name")
      fi
    done < <(echo "$state" | jq -r '.workspaces | keys[]')
  else
    log_error "削除対象を指定してください: <name>, --all, --merged"
    echo "Usage: maw cleanup [<name>|--all|--merged] [--dry-run]"
    exit 1
  fi

  if [[ ${#targets[@]} -eq 0 ]]; then
    log_info "削除対象のワークスペースがありません。"
    return 0
  fi

  # 削除実行
  for name in "${targets[@]}"; do
    local ws_path="${root}/${MAW_WORKSPACES_DIR}/${name}"
    local branch
    branch="$(echo "$state" | jq -r --arg name "$name" '.workspaces[$name].branch')"

    if [[ "$dry_run" == true ]]; then
      log_info "[dry-run] 削除対象: ${name} (branch: ${branch})"
      continue
    fi

    log_info "ワークスペース '${name}' を削除しています..."

    # worktree 削除
    if [[ -d "$ws_path" ]]; then
      (cd "$root" && git worktree remove "$ws_path" --force) 2>/dev/null || {
        log_warn "worktree の正常削除に失敗。強制削除します。"
        rm -rf "$ws_path"
        (cd "$root" && git worktree prune) 2>/dev/null || true
      }
    fi

    # ブランチ削除
    (cd "$root" && git branch -D "$branch") 2>/dev/null || true

    # handover 削除
    rm -f "${root}/${MAW_HANDOVERS_DIR}/ws-${name}.md"

    # claims 連動削除 (当該 WS の全 claim を解除)
    local claims
    claims="$(read_claims "$root")"
    claims="$(echo "$claims" | jq --arg ws "$name" \
      '.claims |= with_entries(select(.value.workspace != $ws))')"
    write_claims "$root" "$claims"

    # state 更新
    remove_workspace_state "$root" "$name"

    log_success "削除完了: ${name}"
  done

  if [[ "$dry_run" == false ]]; then
    log_success "クリーンアップ完了 (${#targets[@]} ワークスペース)"
  fi
}
