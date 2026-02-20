#!/usr/bin/env bash
# core.sh - maw 共通関数

readonly MAW_META_DIR=".maw"
readonly MAW_WORKSPACES_DIR=".maw-workspaces"
readonly MAW_CONFIG_FILE="${MAW_META_DIR}/config.json"
readonly MAW_STATE_FILE="${MAW_META_DIR}/state.json"
readonly MAW_CLAIMS_FILE="${MAW_META_DIR}/claims.json"
readonly MAW_LOCKFILE_HASH="${MAW_META_DIR}/lockfile-hash"
readonly MAW_HANDOVERS_DIR="${MAW_META_DIR}/handovers"

# ログ出力
log_info() {
  echo -e "\033[34m[maw]\033[0m $*"
}

log_success() {
  echo -e "\033[32m[maw]\033[0m $*"
}

log_warn() {
  echo -e "\033[33m[maw]\033[0m $*"
}

log_error() {
  echo -e "\033[31m[maw]\033[0m $*" >&2
}

# プロジェクトルート (.maw/ が存在するディレクトリ) を探索
find_maw_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "${dir}/${MAW_META_DIR}" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# プロジェクトルートを取得 (見つからなければエラー)
require_maw_root() {
  local root
  if ! root="$(find_maw_root)"; then
    log_error "maw プロジェクトが見つかりません。'maw init' を実行してください。"
    exit 1
  fi
  echo "$root"
}

# git リポジトリのルートを取得
find_git_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

# config.json を読み取り
read_config() {
  local root="$1"
  local key="$2"
  jq -r "${key}" "${root}/${MAW_CONFIG_FILE}" 2>/dev/null
}

# config.json 全体を取得
get_config() {
  local root="$1"
  cat "${root}/${MAW_CONFIG_FILE}" 2>/dev/null
}

# state.json を読み取り
read_state() {
  local root="$1"
  cat "${root}/${MAW_STATE_FILE}" 2>/dev/null || echo '{"workspaces":{}}'
}

# state.json を更新
write_state() {
  local root="$1"
  local data="$2"
  echo "$data" | jq '.' > "${root}/${MAW_STATE_FILE}"
}

# state.json にワークスペースを追加
add_workspace_state() {
  local root="$1"
  local name="$2"
  local branch="$3"
  local agent="${4:-}"
  local issue="${5:-}"

  local state
  state="$(read_state "$root")"

  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local new_entry
  new_entry=$(jq -n \
    --arg branch "$branch" \
    --arg agent "$agent" \
    --arg issue "$issue" \
    --arg created "$now" \
    --arg status "active" \
    '{branch: $branch, agent: $agent, issue: $issue, created: $created, status: $status}')

  state=$(echo "$state" | jq --arg name "$name" --argjson entry "$new_entry" \
    '.workspaces[$name] = $entry')

  write_state "$root" "$state"
}

# state.json からワークスペースを削除
remove_workspace_state() {
  local root="$1"
  local name="$2"

  local state
  state="$(read_state "$root")"
  state=$(echo "$state" | jq --arg name "$name" 'del(.workspaces[$name])')
  write_state "$root" "$state"
}

# lockfile からパッケージマネージャを検出
detect_pkg_manager() {
  local root="$1"

  if [[ -f "${root}/yarn.lock" ]]; then
    echo "yarn"
  elif [[ -f "${root}/pnpm-lock.yaml" ]]; then
    echo "pnpm"
  elif [[ -f "${root}/bun.lockb" ]] || [[ -f "${root}/bun.lock" ]]; then
    echo "bun"
  elif [[ -f "${root}/package-lock.json" ]]; then
    echo "npm"
  else
    echo ""
  fi
}

# lockfile のパスを取得
get_lockfile_path() {
  local root="$1"
  local pm="$2"

  case "$pm" in
    yarn) echo "${root}/yarn.lock" ;;
    npm)  echo "${root}/package-lock.json" ;;
    pnpm) echo "${root}/pnpm-lock.yaml" ;;
    bun)
      if [[ -f "${root}/bun.lockb" ]]; then
        echo "${root}/bun.lockb"
      else
        echo "${root}/bun.lock"
      fi
      ;;
    *)    echo "" ;;
  esac
}

# lockfile の SHA-256 ハッシュを計算
compute_lockfile_hash() {
  local filepath="$1"

  if [[ ! -f "$filepath" ]]; then
    echo ""
    return
  fi

  if command -v sha256sum &>/dev/null; then
    sha256sum "$filepath" | awk '{print $1}'
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "$filepath" | awk '{print $1}'
  else
    log_warn "sha256sum / shasum が見つかりません。ハッシュ検証をスキップします。"
    echo ""
  fi
}

# .gitignore にパターンを追加 (重複チェック付き)
ensure_gitignore() {
  local root="$1"
  shift
  local patterns=("$@")
  local gitignore="${root}/.gitignore"

  for pattern in "${patterns[@]}"; do
    if [[ -f "$gitignore" ]]; then
      if ! grep -qxF "$pattern" "$gitignore"; then
        echo "$pattern" >> "$gitignore"
      fi
    else
      echo "$pattern" > "$gitignore"
    fi
  done
}

# 現在のブランチ名を取得
current_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null
}

# ブランチがマージ済みかチェック
is_branch_merged() {
  local branch="$1"
  local base="${2:-main}"

  git branch --merged "$base" 2>/dev/null | grep -qw "$branch"
}
