#!/usr/bin/env bash
# doctor.sh - maw doctor コマンド

cmd_doctor() {
  local fix=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fix) fix=true; shift ;;
      -h|--help)
        echo "Usage: maw doctor [--fix]"
        echo ""
        echo "Options:"
        echo "  --fix    検出された問題を自動修復"
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

  local issues=0
  local fixed=0

  log_info "環境チェックを実行しています..."
  echo ""

  # 1. orphaned worktree チェック
  echo "=== Worktree 整合性 ==="
  local state
  state="$(read_state "$root")"

  # state にあるが worktree が存在しない
  while IFS= read -r name; do
    local ws_path="${root}/${MAW_WORKSPACES_DIR}/${name}"
    if [[ ! -d "$ws_path" ]]; then
      log_warn "orphaned state: '${name}' - worktree が存在しません"
      ((issues++)) || true
      if [[ "$fix" == true ]]; then
        remove_workspace_state "$root" "$name"
        log_success "  -> state から削除しました"
        ((fixed++)) || true
      fi
    fi
  done < <(echo "$state" | jq -r '.workspaces | keys[]' 2>/dev/null)

  # worktree が存在するが state にない
  if [[ -d "${root}/${MAW_WORKSPACES_DIR}" ]]; then
    for ws_dir in "${root}/${MAW_WORKSPACES_DIR}"/*/; do
      [[ -d "$ws_dir" ]] || continue
      local ws_name
      ws_name="$(basename "$ws_dir")"
      if ! echo "$state" | jq -e --arg name "$ws_name" '.workspaces[$name]' &>/dev/null; then
        log_warn "orphaned worktree: '${ws_name}' - state に記録がありません"
        ((issues++)) || true
        if [[ "$fix" == true ]]; then
          log_info "  -> 'maw cleanup ${ws_name}' で削除してください"
        fi
      fi
    done
  fi

  # 2. symlink 整合性チェック
  echo ""
  echo "=== Symlink 整合性 ==="
  local symlink_dirs
  symlink_dirs="$(read_config "$root" '.symlinkDirs[]' 2>/dev/null)" || true

  if [[ -n "$symlink_dirs" ]]; then
    while IFS= read -r name; do
      local ws_path="${root}/${MAW_WORKSPACES_DIR}/${name}"
      [[ -d "$ws_path" ]] || continue

      while IFS= read -r dir; do
        local link="${ws_path}/${dir}"
        local source_dir="${root}/${dir}"

        if [[ -L "$link" ]]; then
          local target
          target="$(readlink "$link")"
          local resolved
          resolved="$(cd "$ws_path" && realpath "$target" 2>/dev/null)" || resolved=""
          local expected
          expected="$(realpath "$source_dir" 2>/dev/null)" || expected=""

          if [[ "$resolved" != "$expected" ]]; then
            log_warn "不正な symlink: ${name}/${dir} -> ${target}"
            ((issues++)) || true
            if [[ "$fix" == true ]]; then
              rm -f "$link"
              local rel_path
              rel_path="$(python3 -c "import os.path; print(os.path.relpath('${source_dir}', '${ws_path}'))" 2>/dev/null)" || \
              rel_path="../../${dir}"
              ln -s "$rel_path" "$link"
              log_success "  -> symlink を修復しました"
              ((fixed++)) || true
            fi
          fi
        elif [[ -d "$source_dir" && ! -e "$link" ]]; then
          log_warn "symlink なし: ${name}/${dir}"
          ((issues++)) || true
          if [[ "$fix" == true ]]; then
            local rel_path
            rel_path="$(python3 -c "import os.path; print(os.path.relpath('${source_dir}', '${ws_path}'))" 2>/dev/null)" || \
            rel_path="../../${dir}"
            ln -s "$rel_path" "$link"
            log_success "  -> symlink を作成しました"
            ((fixed++)) || true
          fi
        fi
      done <<< "$symlink_dirs"
    done < <(echo "$state" | jq -r '.workspaces | keys[]' 2>/dev/null)
  fi

  # 3. lockfile hash チェック
  echo ""
  echo "=== Lockfile 整合性 ==="
  local pm
  pm="$(read_config "$root" '.packageManager')"

  if [[ -n "$pm" && "$pm" != "null" && "$pm" != "" ]]; then
    local lockfile_path
    lockfile_path="$(get_lockfile_path "$root" "$pm")"
    local saved_hash=""
    if [[ -f "${root}/${MAW_LOCKFILE_HASH}" ]]; then
      saved_hash="$(cat "${root}/${MAW_LOCKFILE_HASH}")"
    fi

    if [[ -n "$lockfile_path" && -f "$lockfile_path" ]]; then
      local current_hash
      current_hash="$(compute_lockfile_hash "$lockfile_path")"

      if [[ -n "$saved_hash" && -n "$current_hash" && "$saved_hash" != "$current_hash" ]]; then
        log_warn "lockfile が変更されています。ワークスペースの依存が古い可能性があります。"
        ((issues++)) || true
        if [[ "$fix" == true ]]; then
          echo "$current_hash" > "${root}/${MAW_LOCKFILE_HASH}"
          log_success "  -> lockfile hash を更新しました"
          log_info "  -> 各ワークスペースで '${pm} install' を実行してください (--isolated の場合)"
          ((fixed++)) || true
        fi
      else
        log_success "lockfile hash: 一致"
      fi
    fi
  else
    log_info "パッケージマネージャ未検出 (スキップ)"
  fi

  # 4. git worktree prune チェック
  echo ""
  echo "=== Git Worktree ==="
  local prune_output
  prune_output="$(cd "$root" && git worktree list --porcelain 2>/dev/null | grep -c "^worktree")" || prune_output="0"
  log_info "登録済み worktree: ${prune_output}"

  local stale
  stale="$(cd "$root" && git worktree list 2>/dev/null | grep -c "prunable")" || stale="0"
  if [[ "$stale" -gt 0 ]]; then
    log_warn "prunable な worktree: ${stale}"
    ((issues++)) || true
    if [[ "$fix" == true ]]; then
      (cd "$root" && git worktree prune)
      log_success "  -> prune 実行しました"
      ((fixed++)) || true
    fi
  fi

  # サマリー
  echo ""
  echo "=== サマリー ==="
  if [[ "$issues" -eq 0 ]]; then
    log_success "問題なし"
  else
    if [[ "$fix" == true ]]; then
      log_info "検出: ${issues} 件 / 修復: ${fixed} 件"
    else
      log_warn "問題: ${issues} 件 — 'maw doctor --fix' で修復できます"
    fi
  fi
}
