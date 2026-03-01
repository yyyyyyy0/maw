#!/usr/bin/env bash
# spawn.sh - maw spawn コマンド

# shellcheck source=lib/validate.sh
source "${LIB_DIR}/validate.sh"

cmd_spawn() {
  local name=""
  local branch=""
  local issue=""
  local agent=""
  local isolated=false
  local from_branch=""

  # 引数パース
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch)  branch="$2"; shift 2 ;;
      --issue)   issue="$2"; shift 2 ;;
      --agent)   agent="$2"; shift 2 ;;
      --isolated) isolated=true; shift ;;
      --from)    from_branch="$2"; shift 2 ;;
      -h|--help)
        echo "Usage: maw spawn <name> [options]"
        echo ""
        echo "Options:"
        echo "  --branch <name>    ブランチ名を直接指定"
        echo "  --issue <number>   Issue 番号を紐付け"
        echo "  --agent <name>     エージェント種別 (claude, codex 等)"
        echo "  --isolated         独立依存環境 (symlink ではなく install)"
        echo "  --from <branch>    分岐元ブランチ (デフォルト: origin/main を fetch 後に使用)"
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

  if [[ -z "$name" ]]; then
    log_error "ワークスペース名を指定してください。"
    echo "Usage: maw spawn <name> [options]"
    exit 1
  fi

  local root
  root="$(require_maw_root)"

  # ワークスペース名バリデーション（セキュリティ対策）
  if ! validate_workspace_name "$name"; then
    exit 1
  fi

  # 重複チェック
  local ws_path="${root}/${MAW_WORKSPACES_DIR}/${name}"
  if [[ -d "$ws_path" ]]; then
    log_error "ワークスペース '${name}' は既に存在します。"
    exit 1
  fi

  # ブランチ名決定
  if [[ -z "$branch" ]]; then
    if [[ -n "$issue" && -n "$agent" ]]; then
      branch="${agent}/issue-${issue}-${name}"
    elif [[ -n "$issue" ]]; then
      branch="issue/${issue}-${name}"
    elif [[ -n "$agent" ]]; then
      branch="${agent}/${name}"
    else
      branch="maw/${name}"
    fi
  fi

  # 分岐元ブランチ
  if [[ -z "$from_branch" ]]; then
    if ! (cd "$root" && git fetch origin main --prune); then
      log_error "origin/main の取得に失敗しました。--from <branch> を指定して再実行してください。"
      exit 1
    fi

    if ! (cd "$root" && git show-ref --verify --quiet refs/remotes/origin/main); then
      log_error "origin/main が見つかりません。--from <branch> を指定して再実行してください。"
      exit 1
    fi

    from_branch="origin/main"
  fi

  log_info "ワークスペース '${name}' を作成しています..."
  log_info "ブランチ: ${branch} (from: ${from_branch})"

  # git worktree 作成
  (cd "$root" && git worktree add "${MAW_WORKSPACES_DIR}/${name}" -b "$branch" "$from_branch") || {
    log_error "worktree の作成に失敗しました。"
    exit 1
  }

  # symlink 作成 (--isolated でなければ)
  if [[ "$isolated" == false ]]; then
    local symlink_dirs
    symlink_dirs="$(read_config "$root" '.symlinkDirs[]' 2>/dev/null)" || true

    if [[ -n "$symlink_dirs" ]]; then
      while IFS= read -r dir; do
        local source_dir="${root}/${dir}"
        local target_link="${ws_path}/${dir}"

        if [[ -d "$source_dir" ]]; then
          # 既存があれば削除
          if [[ -e "$target_link" ]]; then
            rm -rf "$target_link"
          fi

          # 相対パスで symlink（安全な関数使用）
          local rel_path
          rel_path="$(calculate_relative_path "$source_dir" "$ws_path")" || \
          rel_path="../../${dir}"

          ln -s "$rel_path" "$target_link"
          log_info "symlink: ${dir} -> ${rel_path}"
        fi
      done <<< "$symlink_dirs"
    fi
  else
    # --isolated: パッケージマネージャで install
    local pm
    pm="$(read_config "$root" '.packageManager')"
    if [[ -n "$pm" && "$pm" != "null" ]]; then
      log_info "依存パッケージを独立インストールしています..."
      (cd "$ws_path" && "${pm}" install) || {
        log_warn "依存パッケージのインストールに失敗しました。"
      }
    fi
  fi

  # dotfiles コピー
  local copy_files
  copy_files="$(read_config "$root" '.copyFiles[]' 2>/dev/null)" || true

  if [[ -n "$copy_files" ]]; then
    while IFS= read -r file; do
      if [[ -f "${root}/${file}" ]]; then
        cp "${root}/${file}" "${ws_path}/${file}"
        log_info "コピー: ${file}"
      fi
    done <<< "$copy_files"
  fi

  # state.json 更新
  add_workspace_state "$root" "$name" "$branch" "$agent" "$issue"

  log_success "ワークスペース '${name}' を作成しました。"
  echo ""
  log_info "パス: ${ws_path}"
  log_info "ブランチ: ${branch}"

  # エージェント起動コマンドの案内
  echo ""
  if [[ -n "$agent" ]]; then
    case "$agent" in
      claude)
        log_info "起動コマンド:"
        echo "  cd ${ws_path} && claude"
        ;;
      codex)
        log_info "起動コマンド:"
        echo "  cd ${ws_path} && codex"
        ;;
      *)
        log_info "作業ディレクトリ:"
        echo "  cd ${ws_path}"
        ;;
    esac
  else
    log_info "作業ディレクトリ:"
    echo "  cd ${ws_path}"
  fi
}
