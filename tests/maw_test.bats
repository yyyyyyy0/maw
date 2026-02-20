#!/usr/bin/env bats

# テスト用ヘルパー
setup() {
  MAW_BIN="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/bin/maw"
  TEST_DIR="$(mktemp -d)"
  cd "$TEST_DIR"

  # テスト用 git リポジトリ作成
  git init --initial-branch=main
  git config user.email "test@example.com"
  git config user.name "Test User"
  echo '{}' > package.json
  echo '# test' > yarn.lock
  git add .
  git commit -m "initial commit"
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

# ===== バージョン表示 =====

@test "maw --version はバージョンを表示する" {
  run "$MAW_BIN" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^maw\ v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "maw -v はバージョンを表示する" {
  run "$MAW_BIN" -v
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^maw\ v ]]
}

# ===== ヘルプ =====

@test "maw --help はヘルプを表示する" {
  run "$MAW_BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "引数なしの maw はヘルプを表示する" {
  run "$MAW_BIN"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

# ===== 不明なコマンド =====

@test "不明なコマンドでエラーを返す" {
  run "$MAW_BIN" unknown-command
  [ "$status" -eq 1 ]
  [[ "$output" =~ "不明なコマンド" ]]
}

# ===== maw init =====

@test "maw init で .maw/ が作成される" {
  run "$MAW_BIN" init
  [ "$status" -eq 0 ]
  [ -d ".maw" ]
  [ -d ".maw-workspaces" ]
  [ -f ".maw/config.json" ]
  [ -f ".maw/state.json" ]
  [ -f ".maw/claims.json" ]
}

@test "maw init でパッケージマネージャが検出される" {
  run "$MAW_BIN" init
  [ "$status" -eq 0 ]
  local pm
  pm="$(jq -r '.packageManager' .maw/config.json)"
  [ "$pm" = "yarn" ]
}

@test "maw init で .gitignore が更新される" {
  run "$MAW_BIN" init
  [ "$status" -eq 0 ]
  grep -qxF ".maw/" .gitignore
  grep -qxF ".maw-workspaces/" .gitignore
}

@test "maw init の二重実行は警告を出す" {
  "$MAW_BIN" init
  run "$MAW_BIN" init
  [ "$status" -eq 0 ]
  [[ "$output" =~ "既に初期化済み" ]]
}

@test "maw init で lockfile hash が保存される" {
  run "$MAW_BIN" init
  [ "$status" -eq 0 ]
  [ -f ".maw/lockfile-hash" ]
  local hash
  hash="$(cat .maw/lockfile-hash)"
  [ -n "$hash" ]
}

@test "maw init で config.json の symlinkDirs が設定される" {
  run "$MAW_BIN" init
  [ "$status" -eq 0 ]
  local dirs
  dirs="$(jq -r '.symlinkDirs[0]' .maw/config.json)"
  [ "$dirs" = "node_modules" ]
}

# ===== maw spawn =====

@test "maw spawn でワークスペースが作成される" {
  "$MAW_BIN" init
  run "$MAW_BIN" spawn test-ws
  [ "$status" -eq 0 ]
  [ -d ".maw-workspaces/test-ws" ]
}

@test "maw spawn --agent でブランチ名にエージェント名が含まれる" {
  "$MAW_BIN" init
  run "$MAW_BIN" spawn test-ws --agent claude
  [ "$status" -eq 0 ]
  local branch
  branch="$(jq -r '.workspaces["test-ws"].branch' .maw/state.json)"
  [ "$branch" = "claude/test-ws" ]
}

@test "maw spawn --issue でブランチ名に Issue 番号が含まれる" {
  "$MAW_BIN" init
  run "$MAW_BIN" spawn test-ws --issue 42
  [ "$status" -eq 0 ]
  local branch
  branch="$(jq -r '.workspaces["test-ws"].branch' .maw/state.json)"
  [ "$branch" = "issue/42-test-ws" ]
}

@test "maw spawn --agent --issue で両方が含まれる" {
  "$MAW_BIN" init
  run "$MAW_BIN" spawn test-ws --agent claude --issue 42
  [ "$status" -eq 0 ]
  local branch
  branch="$(jq -r '.workspaces["test-ws"].branch' .maw/state.json)"
  [ "$branch" = "claude/issue-42-test-ws" ]
}

@test "maw spawn で state.json が更新される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test-ws
  local status_val
  status_val="$(jq -r '.workspaces["test-ws"].status' .maw/state.json)"
  [ "$status_val" = "active" ]
}

@test "maw spawn で symlink が作成される" {
  "$MAW_BIN" init
  mkdir -p node_modules
  echo "test" > node_modules/.package-lock.json
  "$MAW_BIN" spawn test-ws
  [ -L ".maw-workspaces/test-ws/node_modules" ]
}

@test "maw spawn の重複はエラーを返す" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test-ws
  run "$MAW_BIN" spawn test-ws
  [ "$status" -eq 1 ]
  [[ "$output" =~ "既に存在" ]]
}

@test "maw spawn --branch でブランチ名を直接指定" {
  "$MAW_BIN" init
  run "$MAW_BIN" spawn test-ws --branch custom-branch
  [ "$status" -eq 0 ]
  local branch
  branch="$(jq -r '.workspaces["test-ws"].branch' .maw/state.json)"
  [ "$branch" = "custom-branch" ]
}

@test "maw spawn で名前なしはエラー" {
  "$MAW_BIN" init
  run "$MAW_BIN" spawn
  [ "$status" -eq 1 ]
  [[ "$output" =~ "ワークスペース名を指定" ]]
}

# ===== maw list =====

@test "maw list はワークスペース一覧を表示する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1
  "$MAW_BIN" spawn ws2
  run "$MAW_BIN" list
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ws1" ]]
  [[ "$output" =~ "ws2" ]]
}

@test "maw list でワークスペースなしのメッセージが表示される" {
  "$MAW_BIN" init
  run "$MAW_BIN" list
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ワークスペースがありません" ]]
}

# ===== maw cleanup =====

@test "maw cleanup で特定のワークスペースが削除される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test-ws
  run "$MAW_BIN" cleanup test-ws
  [ "$status" -eq 0 ]
  [ ! -d ".maw-workspaces/test-ws" ]
  local ws
  ws="$(jq -r '.workspaces["test-ws"]' .maw/state.json)"
  [ "$ws" = "null" ]
}

@test "maw cleanup --all で全ワークスペースが削除される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1
  "$MAW_BIN" spawn ws2
  run "$MAW_BIN" cleanup --all
  [ "$status" -eq 0 ]
  [ ! -d ".maw-workspaces/ws1" ]
  [ ! -d ".maw-workspaces/ws2" ]
}

@test "maw cleanup --dry-run で削除されない" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test-ws
  run "$MAW_BIN" cleanup test-ws --dry-run
  [ "$status" -eq 0 ]
  [ -d ".maw-workspaces/test-ws" ]
  [[ "$output" =~ "dry-run" ]]
}

@test "maw cleanup で存在しないワークスペースはエラー" {
  "$MAW_BIN" init
  run "$MAW_BIN" cleanup nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" =~ "見つかりません" ]]
}

# ===== maw doctor =====

@test "maw doctor は問題なしで正常終了する" {
  "$MAW_BIN" init
  run "$MAW_BIN" doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ "問題なし" ]]
}

@test "maw doctor は orphaned state を検出する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test-ws
  # worktree を手動で削除して orphaned 状態にする
  rm -rf ".maw-workspaces/test-ws"
  git worktree prune
  run "$MAW_BIN" doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ "orphaned" ]]
}

@test "maw doctor --fix は orphaned state を修復する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test-ws
  rm -rf ".maw-workspaces/test-ws"
  git worktree prune
  run "$MAW_BIN" doctor --fix
  [ "$status" -eq 0 ]
  local ws
  ws="$(jq -r '.workspaces["test-ws"]' .maw/state.json)"
  [ "$ws" = "null" ]
}
