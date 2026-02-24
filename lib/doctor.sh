#!/usr/bin/env bash
# doctor.sh - maw doctor コマンド

# shellcheck source=lib/validate.sh
source "${LIB_DIR}/validate.sh"

cmd_doctor() {
  local fix=false
  local aggressive=false
  local json_output=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fix) fix=true; shift ;;
      --aggressive) aggressive=true; shift ;;
      --json) json_output=true; shift ;;
      -h|--help)
        echo "Usage: maw doctor [--fix] [--aggressive] [--json]"
        echo ""
        echo "Options:"
        echo "  --fix         検出された問題を自動修復"
        echo "  --aggressive マージ済みブランチや dangling worktree を削除"
        echo "  --json        JSON 形式で出力"
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

  # --json モード
  if [[ "$json_output" == true ]]; then
    cmd_doctor_json_output "$root"
    return 0
  fi

  # --aggressive モード（確認プロンプト付き）
  if [[ "$aggressive" == true ]]; then
    cmd_doctor_aggressive_checks "$root" "$fix"
    return 0
  fi

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
              rel_path="$(calculate_relative_path "$source_dir" "$ws_path")" || \
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
            rel_path="$(calculate_relative_path "$source_dir" "$ws_path")" || \
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

  # 5. claims 整合性チェック
  echo ""
  echo "=== Claims 整合性 ==="
  local claims
  claims="$(read_claims "$root")"
  state="$(read_state "$root")"

  local orphan_claims=()
  while IFS= read -r claim_ws; do
    [[ -z "$claim_ws" ]] && continue
    if ! echo "$state" | jq -e --arg name "$claim_ws" '.workspaces[$name]' &>/dev/null; then
      orphan_claims+=("$claim_ws")
    fi
  done < <(echo "$claims" | jq -r '.claims[].workspace' 2>/dev/null | sort -u)

  if [[ ${#orphan_claims[@]} -gt 0 ]]; then
    for ows in "${orphan_claims[@]}"; do
      log_warn "orphan claim: ワークスペース '${ows}' は存在しません"
      ((issues++)) || true
    done
    if [[ "$fix" == true ]]; then
      for ows in "${orphan_claims[@]}"; do
        claims="$(echo "$claims" | jq --arg ws "$ows" \
          '.claims |= with_entries(select(.value.workspace != $ws))')"
      done
      write_claims "$root" "$claims"
      log_success "  -> orphan claims を削除しました"
      ((fixed++)) || true
    fi
  else
    log_success "claims: 整合性OK"
  fi

  # 6. stale (期限切れ) claims チェック
  echo ""
  echo "=== Stale Claims ==="
  local stale_paths=()
  while IFS=$'\t' read -r claim_path expires_at; do
    [[ -z "$claim_path" ]] && continue
    if is_claim_expired "$expires_at"; then
      stale_paths+=("$claim_path")
      log_warn "期限切れ claim: ${claim_path} (期限: ${expires_at})"
      ((issues++)) || true
    fi
  done < <(echo "$claims" | jq -r '.claims | to_entries[] | [.key, (.value.expires_at // "")] | @tsv' 2>/dev/null)

  if [[ "${#stale_paths[@]}" -eq 0 ]]; then
    log_success "stale claims: なし"
  fi

  if [[ "$fix" == true && "${#stale_paths[@]}" -gt 0 ]]; then
    for sp in "${stale_paths[@]}"; do
      claims="$(echo "$claims" | jq --arg path "$sp" 'del(.claims[$path])')"
    done
    write_claims "$root" "$claims"
    log_success "  -> 期限切れ claims を削除しました"
    ((fixed++)) || true
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

# JSON 出力モード
cmd_doctor_json_output() {
  local root="$1"

  local total_checks=0 passed=0 failed=0 warnings=0 fixable=0
  local checks_json="[]"

  # チェック関数（共通ロジックを抽出）
  run_check() {
    local name="$1"
    local status="$2"  # passed|failed|warning
    local message="$3"
    local fixable_bool="$4"

    ((total_checks++)) || true
    case "$status" in
      passed) ((passed++)) || true ;;
      failed) ((failed++)) || true ;;
      warning) ((warnings++)) || true ;;
    esac
    [[ "$fixable_bool" == "true" ]] && ((fixable++)) || true

    local severity="none"
    [[ "$status" == "failed" ]] && severity="error"
    [[ "$status" == "warning" ]] && severity="warning"

    checks_json="$(echo "$checks_json" | jq --arg name "$name" --arg status "$status" \
      --arg severity "$severity" --arg message "$message" --argjson fixable "$fixable_bool" \
      '. += [{name: $name, status: $status, severity: $severity, message: $message, fixable: $fixable}]')"
  }

  local state
  state="$(read_state "$root")"

  # 1. Worktree 整合性チェック
  while IFS= read -r name; do
    local ws_path="${root}/${MAW_WORKSPACES_DIR}/${name}"
    if [[ ! -d "$ws_path" ]]; then
      run_check "worktree_integrity" "failed" "orphaned state: '${name}'" true
    fi
  done < <(echo "$state" | jq -r '.workspaces | keys[]' 2>/dev/null)

  # まだ成功していれば成功として記録
  if [[ "$passed" -eq 0 && "$failed" -eq 0 && "$warnings" -eq 0 ]]; then
    run_check "worktree_integrity" "passed" "All worktrees match state.json" false
  fi

  # 出力
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  jq -n \
    --argjson version 1 \
    --arg timestamp "$now" \
    --argjson total_checks "$total_checks" \
    --argjson passed "$passed" \
    --argjson failed "$failed" \
    --argjson warnings "$warnings" \
    --argjson fixable "$fixable" \
    --argjson checks "$checks_json" \
    '{
      version: $version,
      timestamp: $timestamp,
      summary: {
        total_checks: $total_checks,
        passed: $passed,
        failed: $failed,
        warnings: $warnings,
        fixable: $fixable
      },
      checks: $checks
    }'
}

# Aggressive モード
cmd_doctor_aggressive_checks() {
  local root="$1"
  local fix="$2"

  log_warn "--aggressive モードはブランチとワークスペースを削除します"
  echo ""

  local confirm="no"
  if [[ "$fix" == true ]]; then
    read -rp "続行するには 'yes' と入力してください: " confirm
    if [[ "$confirm" != "yes" ]]; then
      log_info "キャンセルしました"
      return 0
    fi
  fi

  local issues=0
  local fixed=0

  # 1. マージ済みブランチの worktree 削除
  echo "=== マージ済みブランチのチェック ==="
  local state
  state="$(read_state "$root")"
  local base_branch
  base_branch="$(cd "$root" && current_branch)"

  while IFS= read -r name; do
    local ws_info
    ws_info="$(echo "$state" | jq -r --arg name "$name" '.workspaces[$name]')"
    local branch
    branch="$(echo "$ws_info" | jq -r '.branch')"

    if is_branch_merged "$branch" "$base_branch"; then
      log_warn "マージ済みブランチ: ${name} (${branch})"
      ((issues++)) || true
      if [[ "$fix" == true && "$confirm" == "yes" ]]; then
        cleanup_workspace "$root" "$name"
        remove_workspace_state "$root" "$name"
        log_success "  -> ワークスペースを削除しました: ${name}"
        ((fixed++)) || true
      fi
    fi
  done < <(echo "$state" | jq -r '.workspaces | keys[]' 2>/dev/null)

  # 2. git worktree prune
  echo ""
  echo "=== Git Worktree Prune ==="
  (cd "$root" && git worktree prune)
  log_success "prune 実行しました"

  # 3. 空 handover ファイル削除
  echo ""
  echo "=== 空 Handover ファイル ==="
  local handover_dir="${root}/${MAW_HANDOVERS_DIR}"
  if [[ -d "$handover_dir" ]]; then
    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      local size
      size="$(wc -c < "$file" 2>/dev/null)" || size="0"
      if [[ "$size" -eq 0 ]]; then
        log_warn "空 handover ファイル: $(basename "$file")"
        ((issues++)) || true
        if [[ "$fix" == true && "$confirm" == "yes" ]]; then
          rm -f "$file"
          log_success "  -> 削除しました"
          ((fixed++)) || true
        fi
      fi
    done < <(find "$handover_dir" -name "*.json" -o -name "*.md" 2>/dev/null)
  fi

  # サマリー
  echo ""
  echo "=== サマリー ==="
  if [[ "$issues" -eq 0 ]]; then
    log_success "クリーンです"
  else
    if [[ "$fix" == true ]]; then
      log_info "検出: ${issues} 件 / 削除: ${fixed} 件"
    else
      log_warn "問題: ${issues} 件 — 'maw doctor --fix --aggressive' で削除できます"
    fi
  fi
}
