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

# ===== maw status =====

@test "maw status はワークスペース一覧を表示する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" spawn ws2
  run "$MAW_BIN" status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Workspaces" ]]
  [[ "$output" =~ "ws1" ]]
  [[ "$output" =~ "ws2" ]]
}

@test "maw status でワークスペースなしのメッセージが表示される" {
  "$MAW_BIN" init
  run "$MAW_BIN" status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ワークスペースがありません" ]]
}

@test "maw status は claims セクションを表示する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  # WS 内から claim 実行
  cd ".maw-workspaces/ws1"
  "$MAW_BIN" claim src/auth.ts
  cd "$TEST_DIR"
  run "$MAW_BIN" status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Claims" ]]
  [[ "$output" =~ "src/auth.ts" ]]
}

@test "maw status で claims なしのメッセージが表示される" {
  "$MAW_BIN" init
  run "$MAW_BIN" status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "排他宣言はありません" ]]
}

# ===== maw claim =====

@test "maw claim でファイルを claim できる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  cd ".maw-workspaces/ws1"
  run "$MAW_BIN" claim src/auth.ts
  [ "$status" -eq 0 ]
  cd "$TEST_DIR"
  local claimed_ws
  claimed_ws="$(jq -r '.claims["src/auth.ts"].workspace' .maw/claims.json)"
  [ "$claimed_ws" = "ws1" ]
}

@test "maw claim --workspace でワークスペースを指定できる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  run "$MAW_BIN" claim src/auth.ts --workspace ws1
  [ "$status" -eq 0 ]
  local claimed_ws
  claimed_ws="$(jq -r '.claims["src/auth.ts"].workspace' .maw/claims.json)"
  [ "$claimed_ws" = "ws1" ]
}

@test "maw claim で他 WS の claim と競合するとエラー" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" spawn ws2 --agent codex
  "$MAW_BIN" claim src/auth.ts --workspace ws1
  run "$MAW_BIN" claim src/auth.ts --workspace ws2
  [ "$status" -eq 1 ]
  [[ "$output" =~ "排他競合" ]]
}

@test "maw claim で同一 WS の再 claim は冪等 (更新)" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" claim src/auth.ts --workspace ws1
  run "$MAW_BIN" claim src/auth.ts --workspace ws1
  [ "$status" -eq 0 ]
  local count
  count="$(jq '.claims | length' .maw/claims.json)"
  [ "$count" -eq 1 ]
}

@test "maw claim で対象未指定はエラー" {
  "$MAW_BIN" init
  run "$MAW_BIN" claim
  [ "$status" -eq 1 ]
  [[ "$output" =~ "claim 対象を指定" ]]
}

@test "maw claim でディレクトリを claim できる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  run "$MAW_BIN" claim src/components/ --workspace ws1
  [ "$status" -eq 0 ]
  local claimed_ws
  claimed_ws="$(jq -r '.claims["src/components/"].workspace' .maw/claims.json)"
  [ "$claimed_ws" = "ws1" ]
}

@test "maw claim でディレクトリ配下のファイルが他 WS に claim 済みだと競合" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" spawn ws2 --agent codex
  "$MAW_BIN" claim src/components/Button.tsx --workspace ws1
  run "$MAW_BIN" claim src/components/ --workspace ws2
  [ "$status" -eq 1 ]
  [[ "$output" =~ "排他競合" ]]
}

# ===== maw unclaim =====

@test "maw unclaim で claim を解除できる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" claim src/auth.ts --workspace ws1
  cd ".maw-workspaces/ws1"
  run "$MAW_BIN" unclaim src/auth.ts
  [ "$status" -eq 0 ]
  cd "$TEST_DIR"
  local count
  count="$(jq '.claims | length' .maw/claims.json)"
  [ "$count" -eq 0 ]
}

@test "maw unclaim で他 WS の claim はエラー" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" spawn ws2 --agent codex
  "$MAW_BIN" claim src/auth.ts --workspace ws1
  cd ".maw-workspaces/ws2"
  run "$MAW_BIN" unclaim src/auth.ts
  [ "$status" -eq 1 ]
  [[ "$output" =~ "別のワークスペース" ]]
}

@test "maw unclaim --force で他 WS の claim を強制解除できる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" spawn ws2 --agent codex
  "$MAW_BIN" claim src/auth.ts --workspace ws1
  run "$MAW_BIN" unclaim src/auth.ts --workspace ws2 --force
  [ "$status" -eq 0 ]
  local count
  count="$(jq '.claims | length' .maw/claims.json)"
  [ "$count" -eq 0 ]
}

@test "maw unclaim で存在しない claim はエラー" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  cd ".maw-workspaces/ws1"
  run "$MAW_BIN" unclaim nonexistent.ts
  [ "$status" -eq 1 ]
  [[ "$output" =~ "claim が見つかりません" ]]
}

# ===== maw handover =====

@test "maw handover でドキュメントが生成される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude --issue 42
  run "$MAW_BIN" handover --workspace ws1
  [ "$status" -eq 0 ]
  [ -f ".maw/handovers/ws-ws1.md" ]
}

@test "maw handover にブランチ情報が含まれる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  grep -q "ブランチ" .maw/handovers/ws-ws1.md
  grep -q "claude/ws1" .maw/handovers/ws-ws1.md
}

@test "maw handover にコミット履歴セクションが含まれる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  grep -q "コミット履歴" .maw/handovers/ws-ws1.md
}

@test "maw handover に claims が含まれる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" claim src/auth.ts --workspace ws1
  "$MAW_BIN" handover --workspace ws1
  grep -q "src/auth.ts" .maw/handovers/ws-ws1.md
}

@test "maw handover で WS 未指定かつ検出不可ならエラー" {
  "$MAW_BIN" init
  run "$MAW_BIN" handover
  [ "$status" -eq 1 ]
  [[ "$output" =~ "ワークスペースを検出できません" ]]
}

# ===== cleanup 連動 =====

@test "maw cleanup で claims も連動削除される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" claim src/auth.ts --workspace ws1
  "$MAW_BIN" claim src/db.ts --workspace ws1
  # cleanup 実行
  "$MAW_BIN" cleanup ws1
  local count
  count="$(jq '.claims | length' .maw/claims.json)"
  [ "$count" -eq 0 ]
}

# ===== doctor claims =====

@test "maw doctor は orphan claims を検出する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" claim src/auth.ts --workspace ws1
  # state から WS を手動削除 (orphan claim 作成)
  rm -rf ".maw-workspaces/ws1"
  git worktree prune
  local state
  state="$(jq 'del(.workspaces["ws1"])' .maw/state.json)"
  echo "$state" > .maw/state.json
  run "$MAW_BIN" doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ "orphan claim" ]]
}

@test "maw doctor --fix は orphan claims を削除する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" claim src/auth.ts --workspace ws1
  rm -rf ".maw-workspaces/ws1"
  git worktree prune
  local state
  state="$(jq 'del(.workspaces["ws1"])' .maw/state.json)"
  echo "$state" > .maw/state.json
  run "$MAW_BIN" doctor --fix
  [ "$status" -eq 0 ]
  local count
  count="$(jq '.claims | length' .maw/claims.json)"
  [ "$count" -eq 0 ]
}

# ===== maw merge =====

@test "maw merge でブランチが main にマージされる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test-ws
  # ワークスペース内でコミット作成
  cd ".maw-workspaces/test-ws"
  echo "merged content" > merged.txt
  git add merged.txt
  git commit -m "test commit for merge"
  cd "$TEST_DIR"
  run "$MAW_BIN" merge test-ws
  [ "$status" -eq 0 ]
  # main でコミットが存在することを確認
  run git log --oneline
  [[ "$output" =~ "test commit for merge" ]]
}

@test "maw merge 後にワークスペースが削除される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test-ws
  cd ".maw-workspaces/test-ws"
  echo "x" > x.txt
  git add x.txt
  git commit -m "test"
  cd "$TEST_DIR"
  run "$MAW_BIN" merge test-ws
  [ "$status" -eq 0 ]
  [ ! -d ".maw-workspaces/test-ws" ]
  local ws
  ws="$(jq -r '.workspaces["test-ws"]' .maw/state.json)"
  [ "$ws" = "null" ]
}

@test "maw merge --no-cleanup でワークスペースが保持される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test-ws
  cd ".maw-workspaces/test-ws"
  echo "x" > x.txt
  git add x.txt
  git commit -m "test"
  cd "$TEST_DIR"
  run "$MAW_BIN" merge test-ws --no-cleanup
  [ "$status" -eq 0 ]
  [ -d ".maw-workspaces/test-ws" ]
}

@test "maw merge --dry-run では実際のマージが実行されない" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test-ws
  cd ".maw-workspaces/test-ws"
  echo "x" > x.txt
  git add x.txt
  git commit -m "dry-run test commit"
  cd "$TEST_DIR"
  run "$MAW_BIN" merge test-ws --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ "dry-run" ]]
  # ワークスペースが残っていることを確認
  [ -d ".maw-workspaces/test-ws" ]
  # ブランチがマージされていないことを確認
  run git branch --merged
  [[ ! "$output" =~ "maw/test-ws" ]]
}

@test "maw merge で未コミット変更がある場合はエラー" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test-ws
  # 未コミットのファイルを作成
  echo "dirty" > ".maw-workspaces/test-ws/dirty.txt"
  run "$MAW_BIN" merge test-ws
  [ "$status" -eq 1 ]
  [[ "$output" =~ "未コミット" ]]
}

@test "maw merge 後に claims が削除される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test-ws --agent claude
  "$MAW_BIN" claim src/auth.ts --workspace test-ws
  cd ".maw-workspaces/test-ws"
  echo "x" > x.txt
  git add x.txt
  git commit -m "test"
  cd "$TEST_DIR"
  run "$MAW_BIN" merge test-ws
  [ "$status" -eq 0 ]
  local count
  count="$(jq '.claims | length' .maw/claims.json)"
  [ "$count" -eq 0 ]
}

@test "maw merge で存在しないワークスペース名を指定するとエラー" {
  "$MAW_BIN" init
  run "$MAW_BIN" merge nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" =~ "見つかりません" ]]
}
