#!/usr/bin/env bash
# doctor.sh - maw doctor コマンド

# shellcheck source=lib/validate.sh
source "${LIB_DIR}/validate.sh"

cmd_doctor() {
  local fix=false
  local aggressive=false
  local json_output=false
  local exit_code_mode="simple"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fix) fix=true; shift ;;
      --aggressive) aggressive=true; shift ;;
      --json) json_output=true; shift ;;
      --exit-code-mode)
        exit_code_mode="$2"
        if [[ "$exit_code_mode" != "simple" && "$exit_code_mode" != "multi" ]]; then
          log_error "不正な --exit-code-mode 値: ${exit_code_mode} (simple|multi)"
          exit 1
        fi
        shift 2
        ;;
      -h|--help)
        echo "Usage: maw doctor [--fix] [--aggressive] [--json] [--exit-code-mode simple|multi]"
        echo ""
        echo "Options:"
        echo "  --fix               検出された問題を自動修復"
        echo "  --aggressive        マージ済みブランチや dangling worktree を削除"
        echo "  --json              JSON 形式で出力"
        echo "  --exit-code-mode    Exit code モード (simple|multi, デフォルト: simple)"
        echo "                      simple: 問題なし=0, 問題あり=1"
        echo "                      multi:  問題なし=0, critical=1, warning=2"
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
    cmd_doctor_json_output "$root" "$exit_code_mode"
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
  local exit_code_mode="$2"

  local total_checks=0 passed=0 failed=0 warnings=0 fixable=0
  local checks_json="[]"

  # カテゴリ別スコア
  local worktree_score=100 symlink_score=100 lockfile_score=100 git_score=100 claims_score=100 stale_claims_score=100

  # チェック関数（共通ロジックを抽出）
  run_check() {
    local name="$1"
    local status="$2"  # passed|failed|warning
    local message="$3"
    local fixable_bool="$4"
    local category="$5"  # worktree|symlink|lockfile|git|claims|stale_claims

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
      --arg severity "$severity" --arg message "$message" --argjson fixable "$fixable_bool" --arg cat "$category" \
      '. += [{name: $name, status: $status, severity: $severity, message: $message, fixable: $fixable, category: $cat}]')"

    # カテゴリスコア更新（failed は 0、warning は 70、passed は 100）
    case "$status" in
      failed)
        case "$category" in
          worktree) worktree_score=0 ;;
          symlink) symlink_score=0 ;;
          lockfile) lockfile_score=0 ;;
          git) git_score=0 ;;
          claims) claims_score=0 ;;
          stale_claims) stale_claims_score=0 ;;
        esac
        ;;
      warning)
        case "$category" in
          worktree) [[ $worktree_score -gt 70 ]] && worktree_score=70 ;;
          symlink) [[ $symlink_score -gt 70 ]] && symlink_score=70 ;;
          lockfile) [[ $lockfile_score -gt 70 ]] && lockfile_score=70 ;;
          git) [[ $git_score -gt 70 ]] && git_score=70 ;;
          claims) [[ $claims_score -gt 70 ]] && claims_score=70 ;;
          stale_claims) [[ $stale_claims_score -gt 70 ]] && stale_claims_score=70 ;;
        esac
        ;;
    esac
  }

  local state
  state="$(read_state "$root")"

  # 1. Worktree 整合性チェック
  local worktree_check_done=false
  while IFS= read -r name; do
    local ws_path="${root}/${MAW_WORKSPACES_DIR}/${name}"
    if [[ ! -d "$ws_path" ]]; then
      run_check "worktree_integrity" "failed" "orphaned state: '${name}'" true "worktree"
      worktree_check_done=true
    fi
  done < <(echo "$state" | jq -r '.workspaces | keys[]' 2>/dev/null)

  if [[ "$worktree_check_done" == false ]]; then
    run_check "worktree_integrity" "passed" "All worktrees match state.json" false "worktree"
  fi

  # 2. Symlink 整合性チェック
  local symlink_dirs
  symlink_dirs="$(read_config "$root" '.symlinkDirs[]' 2>/dev/null)" || true
  if [[ -n "$symlink_dirs" ]]; then
    local symlink_issue=false
    while IFS= read -r name; do
      local ws_path="${root}/${MAW_WORKSPACES_DIR}/${name}"
      [[ -d "$ws_path" ]] || continue
      while IFS= read -r dir; do
        local link="${ws_path}/${dir}"
        local source_dir="${root}/${dir}"
        if [[ -L "$link" ]]; then
          local target resolved expected
          target="$(readlink "$link")"
          resolved="$(cd "$ws_path" && realpath "$target" 2>/dev/null)" || resolved=""
          expected="$(realpath "$source_dir" 2>/dev/null)" || expected=""
          if [[ "$resolved" != "$expected" ]]; then
            symlink_issue=true
          fi
        elif [[ -d "$source_dir" && ! -e "$link" ]]; then
          symlink_issue=true
        fi
      done <<< "$symlink_dirs"
    done < <(echo "$state" | jq -r '.workspaces | keys[]' 2>/dev/null)

    if [[ "$symlink_issue" == true ]]; then
      run_check "symlink_integrity" "warning" "symlink issues detected" true "symlink"
      symlink_score=70
    else
      run_check "symlink_integrity" "passed" "All symlinks are valid" false "symlink"
    fi
  else
    run_check "symlink_integrity" "passed" "No symlink dirs configured" false "symlink"
  fi

  # 3. Lockfile hash チェック
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
        run_check "lockfile_hash" "warning" "lockfile changed" true "lockfile"
        lockfile_score=70
      else
        run_check "lockfile_hash" "passed" "lockfile hash matches" false "lockfile"
      fi
    else
      run_check "lockfile_hash" "passed" "No lockfile found" false "lockfile"
    fi
  else
    run_check "lockfile_hash" "passed" "No package manager detected" false "lockfile"
  fi

  # 4. Git worktree prune チェック
  local prune_output
  prune_output="$(cd "$root" && git worktree list --porcelain 2>/dev/null | grep -c "^worktree")" || prune_output="0"
  local stale
  stale="$(cd "$root" && git worktree list 2>/dev/null | grep -c "prunable")" || stale="0"
  if [[ "$stale" -gt 0 ]]; then
    run_check "git_worktree_prune" "warning" "${stale} prunable worktree(s)" true "git"
    git_score=70
  else
    run_check "git_worktree_prune" "passed" "No prunable worktrees" false "git"
  fi

  # 5. Claims 整合性チェック
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
    run_check "claims_integrity" "failed" "${#orphan_claims[@]} orphan claim(s)" true "claims"
    claims_score=0
  else
    run_check "claims_integrity" "passed" "All claims valid" false "claims"
  fi

  # 6. Stale claims チェック
  local stale_count=0
  while IFS=$'\t' read -r claim_path expires_at; do
    [[ -z "$claim_path" ]] && continue
    if is_claim_expired "$expires_at"; then
      ((stale_count++)) || true
    fi
  done < <(echo "$claims" | jq -r '.claims | to_entries[] | [.key, (.value.expires_at // "")] | @tsv' 2>/dev/null)

  if [[ "$stale_count" -gt 0 ]]; then
    run_check "stale_claims" "warning" "${stale_count} expired claim(s)" true "stale_claims"
    stale_claims_score=80
  else
    run_check "stale_claims" "passed" "No expired claims" false "stale_claims"
  fi

  # health_score 計算（カテゴリスコアの平均）
  local health_score
  health_score=$(((worktree_score + symlink_score + lockfile_score + git_score + claims_score + stale_claims_score) / 6))

  # 出力
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # maw_version 取得
  local maw_version="${MAW_VERSION:-unknown}"

  # カテゴリステータス判定
  if [[ $worktree_score -eq 100 ]]; then
    worktree_status="passed"
  elif [[ $worktree_score -eq 0 ]]; then
    worktree_status="failed"
  else
    worktree_status="warning"
  fi

  if [[ $symlink_score -eq 100 ]]; then
    symlink_status="passed"
  elif [[ $symlink_score -eq 0 ]]; then
    symlink_status="failed"
  else
    symlink_status="warning"
  fi

  if [[ $lockfile_score -eq 100 ]]; then
    lockfile_status="passed"
  elif [[ $lockfile_score -eq 0 ]]; then
    lockfile_status="failed"
  else
    lockfile_status="warning"
  fi

  if [[ $git_score -eq 100 ]]; then
    git_status="passed"
  elif [[ $git_score -eq 0 ]]; then
    git_status="failed"
  else
    git_status="warning"
  fi

  if [[ $claims_score -eq 100 ]]; then
    claims_status="passed"
  elif [[ $claims_score -eq 0 ]]; then
    claims_status="failed"
  else
    claims_status="warning"
  fi

  if [[ $stale_claims_score -eq 100 ]]; then
    stale_claims_status="passed"
  elif [[ $stale_claims_score -eq 0 ]]; then
    stale_claims_status="failed"
  else
    stale_claims_status="warning"
  fi

  # 出力を生成
  local json_output
  json_output="$(jq -n \
    --argjson version 2 \
    --arg format "doctor" \
    --arg timestamp "$now" \
    --arg maw_version "$maw_version" \
    --argjson health_score "$health_score" \
    --argjson total_checks "$total_checks" \
    --argjson passed "$passed" \
    --argjson failed "$failed" \
    --argjson warnings "$warnings" \
    --argjson fixable "$fixable" \
    --arg worktree_status "$worktree_status" \
    --argjson worktree_score "$worktree_score" \
    --arg symlink_status "$symlink_status" \
    --argjson symlink_score "$symlink_score" \
    --arg lockfile_status "$lockfile_status" \
    --argjson lockfile_score "$lockfile_score" \
    --arg git_status "$git_status" \
    --argjson git_score "$git_score" \
    --arg claims_status "$claims_status" \
    --argjson claims_score "$claims_score" \
    --arg stale_claims_status "$stale_claims_status" \
    --argjson stale_claims_score "$stale_claims_score" \
    --argjson checks "$checks_json" \
    '{
      version: $version,
      format: $format,
      timestamp: $timestamp,
      maw_version: $maw_version,
      health_score: $health_score,
      summary: {
        total_checks: $total_checks,
        passed: $passed,
        failed: $failed,
        warnings: $warnings,
        fixable: $fixable
      },
      categories: {
        worktree: {status: $worktree_status, score: $worktree_score},
        symlink: {status: $symlink_status, score: $symlink_score},
        lockfile: {status: $lockfile_status, score: $lockfile_score},
        git: {status: $git_status, score: $git_score},
        claims: {status: $claims_status, score: $claims_score},
        stale_claims: {status: $stale_claims_status, score: $stale_claims_score}
      },
      checks: $checks
    }')"

  # 出力
  echo "$json_output"

  # Exit code 分岐
  if [[ "$exit_code_mode" == "multi" ]]; then
    # multi モード: critical=1, warning=2
    if [[ "$failed" -gt 0 ]]; then
      exit 1
    elif [[ "$warnings" -gt 0 ]]; then
      exit 2
    fi
  else
    # simple モード（デフォルト）: 問題あり=1
    if [[ "$failed" -gt 0 ]]; then
      exit 1
    fi
  fi
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
