#!/usr/bin/env bash
# merge.sh - maw merge コマンド

cmd_merge() {
  local name=""
  local base_branch=""
  local no_cleanup=false
  local dry_run=false

  # 引数パース
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base)
        base_branch="$2"
        shift 2
        ;;
      --no-cleanup) no_cleanup=true; shift ;;
      --dry-run)    dry_run=true; shift ;;
      -h|--help)
        echo "Usage: maw merge [<name>] [--base <branch>] [--no-cleanup] [--dry-run]"
        echo ""
        echo "Options:"
        echo "  <name>            マージするワークスペース名 (省略時: 自動検出)"
        echo "  --base <branch>   マージ先ベースブランチ (デフォルト: 現在のブランチ)"
        echo "  --no-cleanup      マージ後にワークスペースを保持"
        echo "  --dry-run         実際のマージを実行せずに確認のみ"
        return 0
        ;;
      -*)
        log_error "不明なオプション: $1"
        exit 1
        ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"
        else
          log_error "引数が多すぎます: $1"
          exit 1
        fi
        shift
        ;;
    esac
  done

  local root
  root="$(require_maw_root)"

  # ワークスペース名の自動検出
  if [[ -z "$name" ]]; then
    if ! name="$(detect_current_workspace "$root")"; then
      log_error "ワークスペースを検出できません。名前を指定するか、ワークスペース内から実行してください。"
      exit 1
    fi
  fi

  # state.json でワークスペース存在確認
  local state
  state="$(read_state "$root")"

  if ! echo "$state" | jq -e --arg name "$name" '.workspaces[$name]' &>/dev/null; then
    log_error "ワークスペース '${name}' が見つかりません。"
    exit 1
  fi

  local branch
  branch="$(echo "$state" | jq -r --arg name "$name" '.workspaces[$name].branch')"

  local ws_path="${root}/${MAW_WORKSPACES_DIR}/${name}"

  # ベースブランチ (デフォルト: root の現在ブランチ)
  if [[ -z "$base_branch" ]]; then
    base_branch="$(cd "$root" && current_branch)"
  fi

  # 事前チェック
  # a. root の現在ブランチが base_branch であることを確認
  local current
  current="$(cd "$root" && current_branch)"
  if [[ "$current" != "$base_branch" ]]; then
    log_error "現在のブランチ '${current}' はマージ先ブランチ '${base_branch}' と異なります。"
    log_error "'${base_branch}' をチェックアウトしてから実行してください。"
    exit 1
  fi

  # b. ws_path 内の未コミット変更チェック
  if [[ -d "$ws_path" ]]; then
    local dirty
    dirty="$(cd "$ws_path" && git status --porcelain 2>/dev/null)" || true
    if [[ -n "$dirty" ]]; then
      log_error "ワークスペース '${name}' に未コミットの変更があります。"
      log_error "コミットまたはスタッシュしてから実行してください。"
      exit 1
    fi
  fi

  # c. claims 確認 → 警告のみ
  local claims
  claims="$(read_claims "$root")"
  local claim_count
  claim_count="$(echo "$claims" | jq --arg ws "$name" \
    '[.claims | to_entries[] | select(.value.workspace == $ws)] | length')"
  if [[ "$claim_count" -gt 0 ]]; then
    log_warn "ワークスペース '${name}' には ${claim_count} 件の claim が残っています。マージ後に削除されます。"
  fi

  # d. base_branch の存在確認
  if ! (cd "$root" && git rev-parse --verify "$base_branch" &>/dev/null); then
    log_error "ベースブランチ '${base_branch}' が見つかりません。"
    exit 1
  fi

  # --dry-run: チェック結果を表示して終了
  if [[ "$dry_run" == true ]]; then
    log_info "[dry-run] マージ対象: ${name}"
    log_info "[dry-run] ブランチ: ${branch} -> ${base_branch}"
    log_info "[dry-run] クリーンアップ: $([[ "$no_cleanup" == false ]] && echo "有効" || echo "無効")"
    log_info "[dry-run] Claims: ${claim_count} 件"
    log_success "dry-run 完了。実際のマージは実行されませんでした。"
    return 0
  fi

  log_info "ブランチ '${branch}' を '${base_branch}' にマージしています..."

  # マージ実行
  if ! (cd "$root" && git merge --no-ff "$branch"); then
    log_error "マージに失敗しました。コンフリクトを解消してから再試行してください。"
    exit 1
  fi

  log_success "マージ完了: ${branch} -> ${base_branch}"

  # claims 削除
  claims="$(read_claims "$root")"
  claims="$(echo "$claims" | jq --arg ws "$name" \
    '.claims |= with_entries(select(.value.workspace != $ws))')"
  write_claims "$root" "$claims"

  if [[ "$claim_count" -gt 0 ]]; then
    log_info "claims ${claim_count} 件を削除しました。"
  fi

  # --no-cleanup でなければワークスペースを削除
  if [[ "$no_cleanup" == false ]]; then
    log_info "ワークスペース '${name}' をクリーンアップしています..."

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

    # state から WS エントリ削除
    remove_workspace_state "$root" "$name"

    log_success "クリーンアップ完了: ${name}"
  else
    log_info "--no-cleanup: ワークスペース '${name}' を保持しています。"
  fi
}
