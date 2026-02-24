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
  [ "$version" -eq 1 ]
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
