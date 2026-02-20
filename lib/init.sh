#!/usr/bin/env bash
# init.sh - maw init コマンド

cmd_init() {
  local root
  root="$(find_git_root)" || {
    log_error "git リポジトリ内で実行してください。"
    exit 1
  }

  if [[ -d "${root}/${MAW_META_DIR}" ]]; then
    log_warn "既に初期化済みです: ${root}/${MAW_META_DIR}"
    return 0
  fi

  log_info "maw を初期化しています..."

  # ディレクトリ作成
  mkdir -p "${root}/${MAW_META_DIR}"
  mkdir -p "${root}/${MAW_WORKSPACES_DIR}"
  mkdir -p "${root}/${MAW_HANDOVERS_DIR}"

  # パッケージマネージャ検出
  local pm
  pm="$(detect_pkg_manager "$root")"

  # symlink 対象のデフォルト設定
  local symlink_dirs='["node_modules"]'
  if [[ -z "$pm" ]]; then
    symlink_dirs='[]'
  fi

  # GitHub 情報取得 (任意)
  local github_config='{}'
  if command -v gh &>/dev/null; then
    local gh_info
    if gh_info="$(gh repo view --json owner,name 2>/dev/null)"; then
      local owner repo
      owner="$(echo "$gh_info" | jq -r '.owner.login')"
      repo="$(echo "$gh_info" | jq -r '.name')"
      github_config=$(jq -n --arg owner "$owner" --arg repo "$repo" \
        '{owner: $owner, repo: $repo}')
    fi
  fi

  # config.json 作成
  jq -n \
    --argjson version 1 \
    --arg packageManager "${pm:-}" \
    --argjson symlinkDirs "$symlink_dirs" \
    --argjson copyFiles '[]' \
    --arg validationCommand "" \
    --argjson github "$github_config" \
    '{
      version: $version,
      packageManager: $packageManager,
      symlinkDirs: $symlinkDirs,
      copyFiles: $copyFiles,
      validationCommand: $validationCommand,
      github: $github
    }' > "${root}/${MAW_CONFIG_FILE}"

  # state.json 初期化
  echo '{"workspaces":{}}' | jq '.' > "${root}/${MAW_STATE_FILE}"

  # claims.json 初期化
  echo '{"claims":{}}' | jq '.' > "${root}/${MAW_CLAIMS_FILE}"

  # lockfile hash 保存
  if [[ -n "$pm" ]]; then
    local lockfile_path
    lockfile_path="$(get_lockfile_path "$root" "$pm")"
    if [[ -n "$lockfile_path" && -f "$lockfile_path" ]]; then
      compute_lockfile_hash "$lockfile_path" > "${root}/${MAW_LOCKFILE_HASH}"
    fi
  fi

  # .gitignore 更新
  ensure_gitignore "$root" ".maw/" ".maw-workspaces/"

  log_success "初期化完了: ${root}"
  if [[ -n "$pm" ]]; then
    log_info "パッケージマネージャ: ${pm}"
  fi
  log_info "設定ファイル: ${root}/${MAW_CONFIG_FILE}"
}
