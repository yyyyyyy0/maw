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
  run "$MAW_BIN" spawn test_ws
  [ "$status" -eq 0 ]
  [ -d ".maw-workspaces/test_ws" ]
}

@test "maw spawn --agent でブランチ名にエージェント名が含まれる" {
  "$MAW_BIN" init
  run "$MAW_BIN" spawn test_ws --agent claude
  [ "$status" -eq 0 ]
  local branch
  branch="$(jq -r '.workspaces["test_ws"].branch' .maw/state.json)"
  [ "$branch" = "claude/test_ws" ]
}

@test "maw spawn --issue でブランチ名に Issue 番号が含まれる" {
  "$MAW_BIN" init
  run "$MAW_BIN" spawn test_ws --issue 42
  [ "$status" -eq 0 ]
  local branch
  branch="$(jq -r '.workspaces["test_ws"].branch' .maw/state.json)"
  [ "$branch" = "issue/42-test_ws" ]
}

@test "maw spawn --agent --issue で両方が含まれる" {
  "$MAW_BIN" init
  run "$MAW_BIN" spawn test_ws --agent claude --issue 42
  [ "$status" -eq 0 ]
  local branch
  branch="$(jq -r '.workspaces["test_ws"].branch' .maw/state.json)"
  [ "$branch" = "claude/issue-42-test_ws" ]
}

@test "maw spawn で state.json が更新される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test_ws
  local status_val
  status_val="$(jq -r '.workspaces["test_ws"].status' .maw/state.json)"
  [ "$status_val" = "active" ]
}

@test "maw spawn で symlink が作成される" {
  "$MAW_BIN" init
  mkdir -p node_modules
  echo "test" > node_modules/.package-lock.json
  "$MAW_BIN" spawn test_ws
  [ -L ".maw-workspaces/test_ws/node_modules" ]
}

@test "maw spawn の重複はエラーを返す" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test_ws
  run "$MAW_BIN" spawn test_ws
  [ "$status" -eq 1 ]
  [[ "$output" =~ "既に存在" ]]
}

@test "maw spawn --branch でブランチ名を直接指定" {
  "$MAW_BIN" init
  run "$MAW_BIN" spawn test_ws --branch custom-branch
  [ "$status" -eq 0 ]
  local branch
  branch="$(jq -r '.workspaces["test_ws"].branch' .maw/state.json)"
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
  "$MAW_BIN" spawn test_ws
  run "$MAW_BIN" cleanup test_ws
  [ "$status" -eq 0 ]
  [ ! -d ".maw-workspaces/test_ws" ]
  local ws
  ws="$(jq -r '.workspaces["test_ws"]' .maw/state.json)"
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
  "$MAW_BIN" spawn test_ws
  run "$MAW_BIN" cleanup test_ws --dry-run
  [ "$status" -eq 0 ]
  [ -d ".maw-workspaces/test_ws" ]
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
  "$MAW_BIN" spawn test_ws
  # worktree を手動で削除して orphaned 状態にする
  rm -rf ".maw-workspaces/test_ws"
  git worktree prune
  run "$MAW_BIN" doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ "orphaned" ]]
}

@test "maw doctor --fix は orphaned state を修復する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test_ws
  rm -rf ".maw-workspaces/test_ws"
  git worktree prune
  run "$MAW_BIN" doctor --fix
  [ "$status" -eq 0 ]
  local ws
  ws="$(jq -r '.workspaces["test_ws"]' .maw/state.json)"
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
  "$MAW_BIN" spawn test_ws
  # ワークスペース内でコミット作成
  cd ".maw-workspaces/test_ws"
  echo "merged content" > merged.txt
  git add merged.txt
  git commit -m "test commit for merge"
  cd "$TEST_DIR"
  run "$MAW_BIN" merge test_ws
  [ "$status" -eq 0 ]
  # main でコミットが存在することを確認
  run git log --oneline
  [[ "$output" =~ "test commit for merge" ]]
}

@test "maw merge 後にワークスペースが削除される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test_ws
  cd ".maw-workspaces/test_ws"
  echo "x" > x.txt
  git add x.txt
  git commit -m "test"
  cd "$TEST_DIR"
  run "$MAW_BIN" merge test_ws
  [ "$status" -eq 0 ]
  [ ! -d ".maw-workspaces/test_ws" ]
  local ws
  ws="$(jq -r '.workspaces["test_ws"]' .maw/state.json)"
  [ "$ws" = "null" ]
}

@test "maw merge --no-cleanup でワークスペースが保持される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test_ws
  cd ".maw-workspaces/test_ws"
  echo "x" > x.txt
  git add x.txt
  git commit -m "test"
  cd "$TEST_DIR"
  run "$MAW_BIN" merge test_ws --no-cleanup
  [ "$status" -eq 0 ]
  [ -d ".maw-workspaces/test_ws" ]
}

@test "maw merge --dry-run では実際のマージが実行されない" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test_ws
  cd ".maw-workspaces/test_ws"
  echo "x" > x.txt
  git add x.txt
  git commit -m "dry-run test commit"
  cd "$TEST_DIR"
  run "$MAW_BIN" merge test_ws --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ "dry-run" ]]
  # ワークスペースが残っていることを確認
  [ -d ".maw-workspaces/test_ws" ]
  # ブランチがマージされていないことを確認
  run git branch --merged
  [[ ! "$output" =~ "maw/test_ws" ]]
}

@test "maw merge で未コミット変更がある場合はエラー" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test_ws
  # 未コミットのファイルを作成
  echo "dirty" > ".maw-workspaces/test_ws/dirty.txt"
  run "$MAW_BIN" merge test_ws
  [ "$status" -eq 1 ]
  [[ "$output" =~ "未コミット" ]]
}

@test "maw merge 後に claims が削除される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn test_ws --agent claude
  "$MAW_BIN" claim src/auth.ts --workspace test_ws
  cd ".maw-workspaces/test_ws"
  echo "x" > x.txt
  git add x.txt
  git commit -m "test"
  cd "$TEST_DIR"
  run "$MAW_BIN" merge test_ws
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

# ===== Phase 4-1: Claim TTL =====

@test "maw claim --ttl で expires_at が設定される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  run "$MAW_BIN" claim src/auth.ts --workspace ws1 --ttl 60
  [ "$status" -eq 0 ]
  local expires
  expires="$(jq -r '.claims["src/auth.ts"].expires_at' .maw/claims.json)"
  [ "$expires" != "null" ]
  [ -n "$expires" ]
}

@test "maw claim で TTL 省略時は expires_at が null になる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" claim src/auth.ts --workspace ws1
  local expires
  expires="$(jq -r '.claims["src/auth.ts"].expires_at' .maw/claims.json)"
  [ "$expires" = "null" ]
}

@test "maw claim --ttl 0 で期限切れ claim が作成される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  # TTL=0 で即時期限切れ
  "$MAW_BIN" claim src/auth.ts --workspace ws1 --ttl 0
  sleep 1
  local expires
  expires="$(jq -r '.claims["src/auth.ts"].expires_at' .maw/claims.json)"
  [ "$expires" != "null" ]
}

@test "maw doctor は期限切れ claim を検出する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" claim src/auth.ts --workspace ws1 --ttl 0
  sleep 1
  run "$MAW_BIN" doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ "期限切れ" ]]
}

@test "maw doctor --fix は期限切れ claim を削除する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" claim src/auth.ts --workspace ws1 --ttl 0
  sleep 1
  run "$MAW_BIN" doctor --fix
  [ "$status" -eq 0 ]
  local count
  count="$(jq '.claims | length' .maw/claims.json)"
  [ "$count" -eq 0 ]
}

@test "maw status は期限切れ claim を EXPIRED 表示する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" claim src/auth.ts --workspace ws1 --ttl 0
  sleep 1
  run "$MAW_BIN" status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "EXPIRED" ]]
}

@test "maw doctor --fix は有効な claim を保持する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" claim src/auth.ts --workspace ws1 --ttl 60
  run "$MAW_BIN" doctor --fix
  [ "$status" -eq 0 ]
  local count
  count="$(jq '.claims | length' .maw/claims.json)"
  [ "$count" -eq 1 ]
}

# ===== Phase 4.5: Ecosystem 汎用化 =====

@test "nodejs プロジェクト (yarn.lock) で ecosystem=nodejs が設定される" {
  run "$MAW_BIN" init
  [ "$status" -eq 0 ]
  local ecosystem
  ecosystem="$(jq -r '.ecosystem' .maw/config.json)"
  [ "$ecosystem" = "nodejs" ]
}

@test "nodejs プロジェクトで symlinkDirs に node_modules が含まれる" {
  run "$MAW_BIN" init
  [ "$status" -eq 0 ]
  local dirs
  dirs="$(jq -r '.symlinkDirs[0]' .maw/config.json)"
  [ "$dirs" = "node_modules" ]
}

@test "python プロジェクトで ecosystem=python が設定される" {
  # yarn.lock を削除して pyproject.toml を作成
  rm -f yarn.lock package.json
  echo '[tool.poetry]' > pyproject.toml
  git add pyproject.toml
  git commit -m "python project"
  run "$MAW_BIN" init
  [ "$status" -eq 0 ]
  local ecosystem
  ecosystem="$(jq -r '.ecosystem' .maw/config.json)"
  [ "$ecosystem" = "python" ]
}

@test "rust プロジェクトで ecosystem=rust が設定される" {
  rm -f yarn.lock package.json
  echo '[package]' > Cargo.toml
  git add Cargo.toml
  git commit -m "rust project"
  run "$MAW_BIN" init
  [ "$status" -eq 0 ]
  local ecosystem
  ecosystem="$(jq -r '.ecosystem' .maw/config.json)"
  [ "$ecosystem" = "rust" ]
}

@test "go プロジェクトで ecosystem=go が設定される" {
  rm -f yarn.lock package.json
  echo 'module example.com/app' > go.mod
  git add go.mod
  git commit -m "go project"
  run "$MAW_BIN" init
  [ "$status" -eq 0 ]
  local ecosystem
  ecosystem="$(jq -r '.ecosystem' .maw/config.json)"
  [ "$ecosystem" = "go" ]
}

@test "lockfile なしのプロジェクトで ecosystem=generic が設定される" {
  rm -f yarn.lock package.json
  git add -A
  git commit -m "generic project" --allow-empty
  run "$MAW_BIN" init
  [ "$status" -eq 0 ]
  local ecosystem
  ecosystem="$(jq -r '.ecosystem' .maw/config.json)"
  [ "$ecosystem" = "generic" ]
}

@test "既存 nodejs プロジェクトで packageManager フィールドが後方互換で残る" {
  run "$MAW_BIN" init
  [ "$status" -eq 0 ]
  local pm
  pm="$(jq -r '.packageManager' .maw/config.json)"
  [ "$pm" = "yarn" ]
}

# ===== Phase 5: handover JSON bundle =====

@test "maw handover が JSON サイドカーを生成する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  run "$MAW_BIN" handover --workspace ws1
  [ "$status" -eq 0 ]
  [ -f ".maw/handovers/ws-ws1.json" ]
  local version
  version="$(jq -r '.version' .maw/handovers/ws-ws1.json)"
  [ "$version" -eq 2 ]
}

@test "handover JSON の必須フィールドが揃っている" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  local json=".maw/handovers/ws-ws1.json"
  [ "$(jq 'has("version")' "$json")" = "true" ]
  [ "$(jq 'has("workspace")' "$json")" = "true" ]
  [ "$(jq 'has("branch")' "$json")" = "true" ]
  [ "$(jq 'has("base_branch")' "$json")" = "true" ]
  [ "$(jq 'has("state")' "$json")" = "true" ]
  [ "$(jq 'has("generated_at")' "$json")" = "true" ]
}

@test "handover JSON の workspace フィールドが正しい" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  local ws
  ws="$(jq -r '.workspace' .maw/handovers/ws-ws1.json)"
  [ "$ws" = "ws1" ]
}

@test "handover JSON の state が clean である（変更なし）" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  local state_val
  state_val="$(jq -r '.state' .maw/handovers/ws-ws1.json)"
  [ "$state_val" = "clean" ]
}

@test "handover JSON の log が配列である" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  local log_type
  log_type="$(jq -r '.log | type' .maw/handovers/ws-ws1.json)"
  [ "$log_type" = "array" ]
}

@test "handover JSON の claims フィールドが存在する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" claim src/auth.ts --workspace ws1
  "$MAW_BIN" handover --workspace ws1
  local claims_type
  claims_type="$(jq -r '.claims | type' .maw/handovers/ws-ws1.json)"
  [ "$claims_type" = "object" ]
  local claimed
  claimed="$(jq -r '.claims["src/auth.ts"].workspace' .maw/handovers/ws-ws1.json)"
  [ "$claimed" = "ws1" ]
}

# ===== Phase 5: handover --scope =====

@test "maw handover --scope summary が md と json を生成する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  run "$MAW_BIN" handover --workspace ws1 --scope summary
  [ "$status" -eq 0 ]
  [ -f ".maw/handovers/ws-ws1.md" ]
  [ -f ".maw/handovers/ws-ws1.json" ]
}

@test "maw handover --scope evidence が md のみ生成する（json なし）" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  run "$MAW_BIN" handover --workspace ws1 --scope evidence
  [ "$status" -eq 0 ]
  [ -f ".maw/handovers/ws-ws1.md" ]
  [ ! -f ".maw/handovers/ws-ws1.json" ]
}

@test "maw handover --scope full がデフォルトと同じく md と json を生成する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  run "$MAW_BIN" handover --workspace ws1 --scope full
  [ "$status" -eq 0 ]
  [ -f ".maw/handovers/ws-ws1.md" ]
  [ -f ".maw/handovers/ws-ws1.json" ]
}

@test "maw handover --scope invalid でエラーになる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  run "$MAW_BIN" handover --workspace ws1 --scope invalid
  [ "$status" -eq 1 ]
  [[ "$output" =~ "不正な --scope 値" ]]
}

# ===== Phase 5: maw takeover =====

@test "maw takeover がプロンプト形式で出力する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" takeover ws1
  [ "$status" -eq 0 ]
  [[ "$output" =~ "# Resume:" ]]
}

@test "maw takeover --format json が JSON を出力する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" takeover ws1 --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null 2>&1
}

@test "maw takeover --format md が Markdown を出力する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" takeover ws1 --format md
  [ "$status" -eq 0 ]
  [[ "$output" =~ "# Handover:" ]]
}

@test "handover JSON がない状態で maw takeover はエラーになる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  run "$MAW_BIN" takeover ws1
  [ "$status" -eq 1 ]
  [[ "$output" =~ "見つかりません" ]]
}

# ===== Phase 6: Handover 編集フラグ =====

@test "maw handover --next-step で next_steps に追加される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" handover --workspace ws1 --next-step "テストを実装する"
  [ "$status" -eq 0 ]
  local steps
  steps="$(jq -r '.next_steps[0]' .maw/handovers/ws-ws1.json)"
  [ "$steps" = "テストを実装する" ]
}

@test "maw handover --decision で decisions に追加される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" handover --workspace ws1 --decision "jsonwebtoken を使用する"
  [ "$status" -eq 0 ]
  local decision
  decision="$(jq -r '.decisions[0].description' .maw/handovers/ws-ws1.json)"
  [ "$decision" = "jsonwebtoken を使用する" ]
  local ts
  ts="$(jq -r '.decisions[0].timestamp' .maw/handovers/ws-ws1.json)"
  [ "$ts" != "null" ]
}

@test "maw handover --risk で risks に追加される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" handover --workspace ws1 --risk "トークン有効期限の設定" --risk-severity high
  [ "$status" -eq 0 ]
  local risk
  risk="$(jq -r '.risks[0].description' .maw/handovers/ws-ws1.json)"
  [ "$risk" = "トークン有効期限の設定" ]
  local severity
  severity="$(jq -r '.risks[0].severity' .maw/handovers/ws-ws1.json)"
  [ "$severity" = "high" ]
}

@test "maw handover --resume-command で resume_commands に追加される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" handover --workspace ws1 --resume-command "npm test"
  [ "$status" -eq 0 ]
  local cmd
  cmd="$(jq -r '.resume_commands[0]' .maw/handovers/ws-ws1.json)"
  [ "$cmd" = "npm test" ]
}

@test "maw handover --verification-status で更新される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" handover --workspace ws1 --verification-status passed
  [ "$status" -eq 0 ]
  local status
  status="$(jq -r '.verification_status' .maw/handovers/ws-ws1.json)"
  [ "$status" = "passed" ]
}

@test "maw handover --risk-severity 不正値でエラー" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" handover --workspace ws1 --risk "test" --risk-severity invalid
  [ "$status" -eq 1 ]
  [[ "$output" =~ "不正な --risk-severity 値" ]]
}

@test "maw handover --verification-status 不正値でエラー" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" handover --workspace ws1 --verification-status invalid
  [ "$status" -eq 1 ]
  [[ "$output" =~ "不正な --verification-status 値" ]]
}

@test "maw handover 編集オプションなしでエラー" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  cd ".maw-workspaces/ws1"
  run "$MAW_BIN" handover --next-step
  [ "$status" -eq 1 ]
}

# ===== Phase 6: Takeover plan スコアリング =====

@test "maw takeover --format plan で score と category が出力される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" takeover ws1 --format plan
  [ "$status" -eq 0 ]
  echo "$output" | jq '.score' >/dev/null 2>&1
  echo "$output" | jq '.category' >/dev/null 2>&1
}

@test "takeover plan の ready カテゴリ (スコア 80+)" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  # verification_status=passed にしてスコアを上げる
  "$MAW_BIN" handover --workspace ws1 --verification-status passed
  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"
  local category
  category="$(echo "$output" | jq -r '.category')"
  [ "$category" = "ready" ] || [ "$category" = "caution" ]
}

@test "takeover plan の blocked カテゴリ (スコア 0-49)" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  # state を dirty にするために未コミット変更を作成
  echo "dirty" > ".maw-workspaces/ws1/dirty.txt"
  # dirty 状態で handover 生成
  "$MAW_BIN" handover --workspace ws1
  # failed と critical risk でスコアを下げる
  "$MAW_BIN" handover --workspace ws1 --verification-status failed
  "$MAW_BIN" handover --workspace ws1 --risk "重大な問題" --risk-severity critical
  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"
  local category
  category="$(echo "$output" | jq -r '.category')"
  [ "$category" = "blocked" ]
}

# ===== Phase 6: Doctor JSON v2 =====

@test "maw doctor --json で version 2 が出力される" {
  "$MAW_BIN" init
  run "$MAW_BIN" doctor --json
  [ "$status" -eq 0 ]
  local version
  version="$(echo "$output" | jq -r '.version')"
  [ "$version" -eq 2 ]
}

@test "doctor JSON v2 に format フィールドがある" {
  "$MAW_BIN" init
  local output
  output="$("$MAW_BIN" doctor --json)"
  local format
  format="$(echo "$output" | jq -r '.format')"
  [ "$format" = "doctor" ]
}

@test "doctor JSON v2 に maw_version フィールドがある" {
  "$MAW_BIN" init
  local output
  output="$("$MAW_BIN" doctor --json)"
  local maw_ver
  maw_ver="$(echo "$output" | jq -r '.maw_version')"
  [ "$maw_ver" != "null" ]
  [ -n "$maw_ver" ]
}

@test "doctor JSON v2 に health_score フィールドがある" {
  "$MAW_BIN" init
  local output
  output="$("$MAW_BIN" doctor --json)"
  local health
  health="$(echo "$output" | jq -r '.health_score')"
  [ "$health" -ge 0 ]
  [ "$health" -le 100 ]
}

@test "doctor JSON v2 に categories オブジェクトがある" {
  "$MAW_BIN" init
  local output
  output="$("$MAW_BIN" doctor --json)"
  echo "$output" | jq '.categories.worktree' >/dev/null 2>&1
  echo "$output" | jq '.categories.symlink' >/dev/null 2>&1
  echo "$output" | jq '.categories.lockfile' >/dev/null 2>&1
  echo "$output" | jq '.categories.git' >/dev/null 2>&1
  echo "$output" | jq '.categories.claims' >/dev/null 2>&1
  echo "$output" | jq '.categories.stale_claims' >/dev/null 2>&1
}

@test "doctor JSON v2 のカテゴリに status と score がある" {
  "$MAW_BIN" init
  local output
  output="$("$MAW_BIN" doctor --json)"
  local status score
  status="$(echo "$output" | jq -r '.categories.worktree.status')"
  score="$(echo "$output" | jq -r '.categories.worktree.score')"
  [ "$status" = "passed" ] || [ "$status" = "warning" ] || [ "$status" = "failed" ]
  [ "$score" -ge 0 ]
  [ "$score" -le 100 ]
}

@test "doctor JSON v2 の checks に category フィールドがある" {
  "$MAW_BIN" init
  local output
  output="$("$MAW_BIN" doctor --json)"
  local count
  count="$(echo "$output" | jq '.checks | length')"
  [ "$count" -gt 0 ]
  local category
  category="$(echo "$output" | jq -r '.checks[0].category')"
  [ "$category" != "null" ]
}

# ===== Phase 6: --blocked-by オプション =====

@test "maw handover --blocked-by で blocked_by に追加される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" handover --workspace ws1 --blocked-by "PR #123 がマージ待ち"
  [ "$status" -eq 0 ]
  local blocked
  blocked="$(jq -r '.blocked_by[0]' .maw/handovers/ws-ws1.json)"
  [ "$blocked" = "PR #123 がマージ待ち" ]
}

@test "maw handover --blocked-by 複数回指定で配列に追加される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker 1"
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker 2"
  local count
  count="$(jq '.blocked_by | length' .maw/handovers/ws-ws1.json)"
  [ "$count" -eq 2 ]
}

@test "maw takeover --format plan で blocked_by が blockers_count に反映される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --blocked-by "依存機能が未実装"
  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"
  local blockers_count
  blockers_count="$(echo "$output" | jq -r '.blockers_count')"
  [ "$blockers_count" -eq 1 ]
}

@test "maw takeover --format plan で blocker 0件は空配列" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local blockers_count
  blockers_count="$(echo "$output" | jq -r '.blockers_count')"
  [ "$blockers_count" -eq 0 ]

  local blockers
  blockers="$(echo "$output" | jq -r '.blockers | length')"
  [ "$blockers" -eq 0 ]
}

@test "maw takeover --format plan で blocker 1件は1件表示" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Single Blocker"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local blockers_count
  blockers_count="$(echo "$output" | jq -r '.blockers_count')"
  [ "$blockers_count" -eq 1 ]

  local blockers
  blockers="$(echo "$output" | jq -r '.blockers | length')"
  [ "$blockers" -eq 1 ]

  local first
  first="$(echo "$output" | jq -r '.blockers[0]')"
  [ "$first" = "Single Blocker" ]
}

@test "maw takeover --format plan で blocker 4件は上位3件のみ表示" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker 1"
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker 2"
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker 3"
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker 4"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  # blockers_count は全件
  local blockers_count
  blockers_count="$(echo "$output" | jq -r '.blockers_count')"
  [ "$blockers_count" -eq 4 ]

  # blockers 配列は上位3件のみ
  local blockers
  blockers="$(echo "$output" | jq -r '.blockers | length')"
  [ "$blockers" -eq 3 ]

  # 順序維持確認
  local first
  first="$(echo "$output" | jq -r '.blockers[0]')"
  [ "$first" = "Blocker 1" ]
}

@test "maw handover --unblock で blocker が削除される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker A"
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker B"

  # Execute: A を削除
  run "$MAW_BIN" handover --workspace ws1 --unblock "Blocker A"
  [ "$status" -eq 0 ]

  # Verify: B のみ残る
  local count
  count="$(jq '.blocked_by | length' .maw/handovers/ws-ws1.json)"
  [ "$count" -eq 1 ]
  local remaining
  remaining="$(jq -r '.blocked_by[0]' .maw/handovers/ws-ws1.json)"
  [ "$remaining" = "Blocker B" ]
}

@test "maw handover --unblock で部分一致で削除される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --blocked-by "PR #123 マージ待ち"
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker B"

  # 部分一致 "123" で削除
  run "$MAW_BIN" handover --workspace ws1 --unblock "123"
  [ "$status" -eq 0 ]

  local count
  count="$(jq '.blocked_by | length' .maw/handovers/ws-ws1.json)"
  [ "$count" -eq 1 ]
}

@test "maw handover --unblock で大文字小文字区別なし" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --blocked-by "PR #ABC"

  # 小文字で指定しても削除される
  run "$MAW_BIN" handover --workspace ws1 --unblock "abc"
  [ "$status" -eq 0 ]

  local count
  count="$(jq '.blocked_by | length' .maw/handovers/ws-ws1.json)"
  [ "$count" -eq 0 ]
}

@test "maw handover --unblock で存在しない blocker は安全に無視" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker A"

  # 存在しない blocker を指定してもエラーにならない
  run "$MAW_BIN" handover --workspace ws1 --unblock "NonExistent"
  [ "$status" -eq 0 ]

  # 元の blocker は残ったまま
  local count
  count="$(jq '.blocked_by | length' .maw/handovers/ws-ws1.json)"
  [ "$count" -eq 1 ]
}

@test "maw handover --clear-blockers で全 blocker が削除される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker A"
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker B"
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker C"

  run "$MAW_BIN" handover --workspace ws1 --clear-blockers
  [ "$status" -eq 0 ]

  local count
  count="$(jq '.blocked_by | length' .maw/handovers/ws-ws1.json)"
  [ "$count" -eq 0 ]
}

@test "maw handover --clear-blockers で blocker 空でも安全" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  # blocker がない状態でクリアしてもエラーにならない
  run "$MAW_BIN" handover --workspace ws1 --clear-blockers
  [ "$status" -eq 0 ]

  local count
  count="$(jq '.blocked_by | length' .maw/handovers/ws-ws1.json)"
  [ "$count" -eq 0 ]
}

# ===== Phase 6: Doctor --json exit code =====

@test "maw doctor --json は問題なしで exit 0" {
  "$MAW_BIN" init
  run "$MAW_BIN" doctor --json
  [ "$status" -eq 0 ]
}

@test "maw doctor --json は問題検出時に 非0 で終了する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1
  # orphaned state を作成
  rm -rf ".maw-workspaces/ws1"
  git worktree prune
  run "$MAW_BIN" doctor --json
  [ "$status" -ne 0 ]
  local failed
  failed="$(echo "$output" | jq -r '.summary.failed')"
  [ "$failed" -gt 0 ]
}

@test "maw doctor --json --exit-code-mode simple は warning-only で exit 0" {
  "$MAW_BIN" init
  # lockfile 変更で warning を作成
  echo "# changed" >> yarn.lock
  git add yarn.lock
  git commit -m "change lockfile"

  run "$MAW_BIN" doctor --json --exit-code-mode simple
  [ "$status" -eq 0 ]

  # JSON は parse 可能
  echo "$output" | jq . >/dev/null
}

@test "maw doctor --json --exit-code-mode simple は failed で exit 1" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1
  # orphaned state を作成
  rm -rf ".maw-workspaces/ws1"
  git worktree prune

  run "$MAW_BIN" doctor --json --exit-code-mode simple
  [ "$status" -eq 1 ]
}

@test "maw doctor --json --exit-code-mode multi は warning-only で exit 2" {
  "$MAW_BIN" init
  # lockfile 変更で warning を作成
  echo "# changed" >> yarn.lock
  git add yarn.lock
  git commit -m "change lockfile"

  run "$MAW_BIN" doctor --json --exit-code-mode multi
  [ "$status" -eq 2 ]
}

@test "maw doctor --json --exit-code-mode multi は failed で exit 1" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1
  rm -rf ".maw-workspaces/ws1"
  git worktree prune

  run "$MAW_BIN" doctor --json --exit-code-mode multi
  [ "$status" -eq 1 ]
}

@test "maw doctor --json --exit-code-mode invalid でエラー" {
  "$MAW_BIN" init
  run "$MAW_BIN" doctor --json --exit-code-mode invalid
  [ "$status" -eq 1 ]
  [[ "$output" =~ "不正な --exit-code-mode 値" ]]
}
