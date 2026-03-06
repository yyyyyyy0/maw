#!/usr/bin/env bats

# テスト用ヘルパー
setup() {
  MAW_BIN="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/bin/maw"
  TEST_DIR="$(mktemp -d)"
  cd "$TEST_DIR"
  REMOTE_DIR="${TEST_DIR}/remote.git"

  # テスト用 git リポジトリ作成
  git init --initial-branch=main
  git config user.email "test@example.com"
  git config user.name "Test User"
  echo '{}' > package.json
  echo '# test' > yarn.lock
  git add .
  git commit -m "initial commit"
  git init --bare "$REMOTE_DIR"
  git remote add origin "$REMOTE_DIR"
  git push -u origin main
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

@test "maw migrate --help はヘルプを表示する" {
  run "$MAW_BIN" migrate --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage: maw migrate" ]]
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

@test "maw spawn デフォルト分岐元は current branch ではなく origin/main" {
  git checkout -b feature/current
  echo "feature-only" > feature-only.txt
  git add feature-only.txt
  git commit -m "feature commit"
  "$MAW_BIN" init
  run "$MAW_BIN" spawn test_ws
  [ "$status" -eq 0 ]
  local ws_head
  ws_head="$(git -C ".maw-workspaces/test_ws" rev-parse HEAD)"
  local origin_main_head
  origin_main_head="$(git rev-parse origin/main)"
  [ "$ws_head" = "$origin_main_head" ]
  [ ! -f ".maw-workspaces/test_ws/feature-only.txt" ]
}

@test "maw spawn は origin/main が利用不可で --from 未指定なら失敗" {
  "$MAW_BIN" init
  git remote remove origin
  run "$MAW_BIN" spawn test_ws
  [ "$status" -eq 1 ]
  [[ "$output" =~ "origin/main" ]]
  [[ "$output" =~ "--from" ]]
}

@test "maw spawn --from main は origin remote 削除後でも成功" {
  "$MAW_BIN" init
  git remote remove origin
  run "$MAW_BIN" spawn test_ws --from main
  [ "$status" -eq 0 ]
  [ -d ".maw-workspaces/test_ws" ]
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

@test "maw takeover --format plan は valid JSON と required top-level keys/type を返す" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" takeover ws1 --format plan
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    type == "object" and
    (has("id") and (.id | type == "string")) and
    (has("summary") and (.summary | type == "string")) and
    (has("evidence_refs") and (.evidence_refs | type == "array") and all(.evidence_refs[]?; type == "string")) and
    (has("workspace") and (.workspace | type == "string")) and
    (has("branch") and (.branch | type == "string")) and
    (has("verification_status") and (.verification_status | type == "string")) and
    (has("state") and (.state | type == "string")) and
    (has("decisions_count") and (.decisions_count | type == "number") and (.decisions_count | floor == . and . >= 0)) and
    (has("risks_count") and (.risks_count | type == "number") and (.risks_count | floor == . and . >= 0)) and
    (has("blockers_count") and (.blockers_count | type == "number") and (.blockers_count | floor == . and . >= 0)) and
    (has("blockers") and (.blockers | type == "array") and all(.blockers[]?; type == "string")) and
    (has("score") and (.score | type == "number") and (.score | floor == . and . >= 0 and . <= 100)) and
    (has("category") and (.category | type == "string")) and
    (has("priority_actions") and (.priority_actions | type == "array")) and
    (has("resume_commands") and (.resume_commands | type == "array") and all(.resume_commands[]?; type == "string"))
  ' >/dev/null
}

@test "takeover plan canonical scoring: passed + clean + no blockers + no risks => 100/ready" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --verification-status passed
  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"
  local score category
  score="$(echo "$output" | jq -r '.score')"
  category="$(echo "$output" | jq -r '.category')"
  [ "$score" -eq 100 ]
  [ "$category" = "ready" ]
}

@test "takeover plan canonical scoring: pending + clean + no blockers + no risks => 72/caution" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local score category
  score="$(echo "$output" | jq -r '.score')"
  category="$(echo "$output" | jq -r '.category')"
  [ "$score" -eq 72 ]
  [ "$category" = "caution" ]
}

@test "takeover plan canonical scoring: failed + dirty + 3 blockers + critical risk => 20/blocked" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  echo "dirty" > ".maw-workspaces/ws1/dirty.txt"
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --verification-status failed
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker 1"
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker 2"
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker 3"
  "$MAW_BIN" handover --workspace ws1 --risk "重大な問題" --risk-severity critical
  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"
  local score category
  score="$(echo "$output" | jq -r '.score')"
  category="$(echo "$output" | jq -r '.category')"
  [ "$score" -eq 20 ]
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

@test "maw doctor --json は required top-level keys/type を返す" {
  "$MAW_BIN" init
  local output
  output="$("$MAW_BIN" doctor --json)"

  echo "$output" | jq -e '
    type == "object" and
    (has("version") and (.version | type == "number") and .version == 2) and
    (has("format") and (.format | type == "string") and .format == "doctor") and
    (has("timestamp") and (.timestamp | type == "string")) and
    (has("maw_version") and (.maw_version | type == "string")) and
    (has("health_score") and (.health_score | type == "number") and (.health_score | floor == . and . >= 0 and . <= 100)) and
    (has("summary") and (.summary | type == "object")) and
    (has("categories") and (.categories | type == "object")) and
    (has("checks") and (.checks | type == "array"))
  ' >/dev/null
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

@test "doctor JSON v2 の summary は required keys/type を返す" {
  "$MAW_BIN" init
  local output
  output="$("$MAW_BIN" doctor --json)"

  echo "$output" | jq -e '
    .summary |
    type == "object" and
    (has("total_checks") and (.total_checks | type == "number") and (.total_checks | floor == . and . >= 0)) and
    (has("passed") and (.passed | type == "number") and (.passed | floor == . and . >= 0)) and
    (has("failed") and (.failed | type == "number") and (.failed | floor == . and . >= 0)) and
    (has("warnings") and (.warnings | type == "number") and (.warnings | floor == . and . >= 0)) and
    (has("fixable") and (.fixable | type == "number") and (.fixable | floor == . and . >= 0)) and
    (.passed + .failed + .warnings == .total_checks)
  ' >/dev/null
}

@test "doctor JSON v2 の summary counts は checks と一致する" {
  "$MAW_BIN" init
  local output
  output="$("$MAW_BIN" doctor --json)"

  echo "$output" | jq -e '
    .summary as $summary |
    .checks as $checks |
    ($checks | length) == $summary.total_checks and
    ([ $checks[] | select(.status == "passed") ] | length) == $summary.passed and
    ([ $checks[] | select(.status == "failed") ] | length) == $summary.failed and
    ([ $checks[] | select(.status == "warning") ] | length) == $summary.warnings and
    ([ $checks[] | select(.fixable == true) ] | length) == $summary.fixable
  ' >/dev/null
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

@test "doctor JSON v2 の categories は required keys/type を返す" {
  "$MAW_BIN" init
  local output
  output="$("$MAW_BIN" doctor --json)"

  echo "$output" | jq -e '
    .categories as $categories |
    ($categories | keys | sort) == ["claims", "git", "lockfile", "stale_claims", "symlink", "worktree"] and
    ([ $categories[] |
      (type == "object") and
      (has("status") and (.status == "passed" or .status == "warning" or .status == "failed")) and
      (has("score") and (.score | type == "number") and (.score | floor == . and . >= 0 and . <= 100))
    ] | all)
  ' >/dev/null
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

@test "doctor JSON v2 の checks entry は required keys/type を返す" {
  "$MAW_BIN" init
  local output
  output="$("$MAW_BIN" doctor --json)"

  echo "$output" | jq -e '
    (.checks | length) > 0 and
    ([.checks[] |
      (type == "object") and
      (has("name") and (.name | type == "string")) and
      (has("status") and (.status == "passed" or .status == "warning" or .status == "failed")) and
      (has("severity") and (.severity == "none" or .severity == "warning" or .severity == "error")) and
      (has("message") and (.message | type == "string")) and
      (has("fixable") and (.fixable | type == "boolean")) and
      (has("category") and (.category == "worktree" or .category == "symlink" or .category == "lockfile" or .category == "git" or .category == "claims" or .category == "stale_claims"))
    ] | all)
  ' >/dev/null
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

@test "maw doctor --json は config.json 欠落時も JSON を返す" {
  "$MAW_BIN" init
  rm -f ".maw/config.json"

  run "$MAW_BIN" doctor --json
  [ "$status" -eq 0 ]

  # エラー終了せず JSON として解釈可能
  echo "$output" | jq . >/dev/null

  local lockfile_msg
  lockfile_msg="$(echo "$output" | jq -r '.checks[] | select(.name == "lockfile_hash") | .message')"
  [ "$lockfile_msg" = "No package manager detected" ]
}

@test "maw doctor --json のデフォルト exit mode は simple で warning-only なら exit 0" {
  "$MAW_BIN" init
  echo "# changed" >> yarn.lock
  git add yarn.lock
  git commit -m "change lockfile"

  run "$MAW_BIN" doctor --json
  [ "$status" -eq 0 ]

  local warnings failed
  warnings="$(echo "$output" | jq -r '.summary.warnings')"
  failed="$(echo "$output" | jq -r '.summary.failed')"
  [ "$warnings" -gt 0 ]
  [ "$failed" -eq 0 ]
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

@test "maw doctor --json --exit-code-mode multi は問題なしで exit 0" {
  "$MAW_BIN" init

  run "$MAW_BIN" doctor --json --exit-code-mode multi
  [ "$status" -eq 0 ]

  local warnings failed
  warnings="$(echo "$output" | jq -r '.summary.warnings')"
  failed="$(echo "$output" | jq -r '.summary.failed')"
  [ "$warnings" -eq 0 ]
  [ "$failed" -eq 0 ]
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

@test "maw takeover --format plan は v2 文字列配列の blocked_by を正しく表示する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker 1"
  "$MAW_BIN" handover --workspace ws1 --blocked-by "Blocker 2"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  # Verify blockers are displayed as strings (backward compatibility)
  local blockers_count
  blockers_count="$(echo "$output" | jq -r '.blockers_count')"
  [ "$blockers_count" -eq 2 ]

  local first
  first="$(echo "$output" | jq -r '.blockers[0]')"
  [ "$first" = "Blocker 1" ]
}

@test "maw takeover --format plan は v3 オブジェクト配列の blocked_by を正しく表示する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  # Manually create v3 handover with object blockers
  local json_file=".maw/handovers/ws-ws1.json"
  local updated
  updated="$(jq '
    .version = 3 |
    .blocked_by = [
      {type: "dependency", description: "Waiting for lib-v2", resolved: false},
      {type: "issue", description: "Design approval needed", resolved: true, resolved_at: "2025-02-25T12:00:00Z"}
    ]
  ' "$json_file")"
  echo "$updated" > "$json_file"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  # Verify descriptions are extracted
  local blockers_count
  blockers_count="$(echo "$output" | jq -r '.blockers_count')"
  [ "$blockers_count" -eq 2 ]

  # Verify descriptions (not full objects)
  local first second
  first="$(echo "$output" | jq -r '.blockers[0]')"
  second="$(echo "$output" | jq -r '.blockers[1]')"
  [ "$first" = "Waiting for lib-v2" ]
  [ "$second" = "Design approval needed" ]
}

@test "maw takeover --format plan は混合配列 (文字列+オブジェクト) を正しく表示する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  # Create mixed format
  local json_file=".maw/handovers/ws-ws1.json"
  local updated
  updated="$(jq '
    .version = 3 |
    .blocked_by = [
      "Simple string blocker",
      {type: "dependency", description: "Complex object blocker", resolved: false}
    ]
  ' "$json_file")"
  echo "$updated" > "$json_file"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  # Both should be displayed as strings
  local blockers_count
  blockers_count="$(echo "$output" | jq -r '.blockers_count')"
  [ "$blockers_count" -eq 2 ]

  local first second
  first="$(echo "$output" | jq -r '.blockers[0]')"
  second="$(echo "$output" | jq -r '.blockers[1]')"
  [ "$first" = "Simple string blocker" ]
  [ "$second" = "Complex object blocker" ]
}

@test "maw takeover --format plan は description なしのオブジェクト blocker をフォールバック表示する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  # Create object without description
  local json_file=".maw/handovers/ws-ws1.json"
  local updated
  updated="$(jq '
    .version = 3 |
    .blocked_by = [
      {type: "dependency", resolved: false}
    ]
  ' "$json_file")"
  echo "$updated" > "$json_file"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local blocker
  blocker="$(echo "$output" | jq -r '.blockers[0]')"
  [ "$blocker" = "[invalid blocker object]" ]
}

@test "maw takeover --format plan は無効なタイプ（null）の blocker をフォールバック表示する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  # Create null entry
  local json_file=".maw/handovers/ws-ws1.json"
  local updated
  updated="$(jq '
    .version = 3 |
    .blocked_by = [null]
  ' "$json_file")"
  echo "$updated" > "$json_file"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local blocker
  blocker="$(echo "$output" | jq -r '.blockers[0]')"
  [ "$blocker" = "[invalid blocker entry]" ]
}

@test "maw takeover --format plan は無効なタイプ（number）の blocker をフォールバック表示する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  # Create number entry
  local json_file=".maw/handovers/ws-ws1.json"
  local updated
  updated="$(jq '
    .version = 3 |
    .blocked_by = [42]
  ' "$json_file")"
  echo "$updated" > "$json_file"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local blocker
  blocker="$(echo "$output" | jq -r '.blockers[0]')"
  [ "$blocker" = "[invalid blocker entry]" ]
}

@test "maw takeover --format plan は無効なタイプ（bool）の blocker をフォールバック表示する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  # Create bool entry
  local json_file=".maw/handovers/ws-ws1.json"
  local updated
  updated="$(jq '
    .version = 3 |
    .blocked_by = [true]
  ' "$json_file")"
  echo "$updated" > "$json_file"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local blocker
  blocker="$(echo "$output" | jq -r '.blockers[0]')"
  [ "$blocker" = "[invalid blocker entry]" ]
}

# ===== v0.7.3: handover v3 object write =====

@test "maw handover --blocked-by-type --blocked-by-desc で v3 object 形式で書き込まれる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 \
    --blocked-by-type dependency \
    --blocked-by-desc "PR #456 waiting"

  local json_file=".maw/handovers/ws-ws1.json"
  local blocker_type blocker_desc blocker_resolved
  blocker_type="$(jq -r '.blocked_by[0].type' "$json_file")"
  blocker_desc="$(jq -r '.blocked_by[0].description' "$json_file")"
  blocker_resolved="$(jq -r '.blocked_by[0].resolved' "$json_file")"

  [ "$blocker_type" = "dependency" ]
  [ "$blocker_desc" = "PR #456 waiting" ]
  [ "$blocker_resolved" = "false" ]
}

@test "maw handover --blocked-by-owner を指定するとオブジェクトに owner フィールドが含まれる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 \
    --blocked-by-type blocker \
    --blocked-by-desc "waiting for decision" \
    --blocked-by-owner nil

  local json_file=".maw/handovers/ws-ws1.json"
  local owner
  owner="$(jq -r '.blocked_by[0].owner' "$json_file")"
  [ "$owner" = "nil" ]
}

@test "maw handover --blocked-by-type のみ指定するとエラー" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" handover --workspace ws1 --blocked-by-type dependency
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--blocked-by-type と --blocked-by-desc は両方指定してください" ]]
}

@test "maw handover --blocked-by-type 不正値はエラー" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" handover --workspace ws1 --blocked-by-type invalid_type --blocked-by-desc "test"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "不正な --blocked-by-type 値" ]]
}

@test "v3 object write → takeover --format json roundtrip" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 \
    --blocked-by-type dependency \
    --blocked-by-desc "PR #456 waiting" \
    --blocked-by-owner nil

  local output
  output="$("$MAW_BIN" takeover ws1 --format json)"

  local bl_type bl_desc bl_owner
  bl_type="$(echo "$output" | jq -r '.blocked_by[0].type')"
  bl_desc="$(echo "$output" | jq -r '.blocked_by[0].description')"
  bl_owner="$(echo "$output" | jq -r '.blocked_by[0].owner')"

  [ "$bl_type" = "dependency" ]
  [ "$bl_desc" = "PR #456 waiting" ]
  [ "$bl_owner" = "nil" ]
}

@test "v3 object write → takeover --format plan で blockers に description が表示される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 \
    --blocked-by-type dependency \
    --blocked-by-desc "外部PR #456 待ち"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local blockers_count first_blocker
  blockers_count="$(echo "$output" | jq -r '.blockers_count')"
  first_blocker="$(echo "$output" | jq -r '.blockers[0]')"

  [ "$blockers_count" -eq 1 ]
  [ "$first_blocker" = "外部PR #456 待ち" ]
}

@test "--unblock は object 形式 blocked_by の description に部分一致で削除する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 \
    --blocked-by-type dependency \
    --blocked-by-desc "PR #456 waiting for merge"
  "$MAW_BIN" handover --workspace ws1 --unblock "PR #456"

  local json_file=".maw/handovers/ws-ws1.json"
  local count
  count="$(jq '.blocked_by | length' "$json_file")"
  [ "$count" -eq 0 ]
}

@test "validate_handover_bundle は description なしのオブジェクトを拒否する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  # description なしのオブジェクトを直接書き込む
  local json_file=".maw/handovers/ws-ws1.json"
  jq '.blocked_by = [{"type": "blocker", "resolved": false}]' "$json_file" > "${json_file}.tmp" \
    && mv "${json_file}.tmp" "$json_file"

  run "$MAW_BIN" handover --validate ws1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "description" ]]
}

@test "validate_handover_bundle は不正な type を拒否する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  local json_file=".maw/handovers/ws-ws1.json"
  jq '.blocked_by = [{"type": "invalid_type", "description": "test", "resolved": false}]' \
    "$json_file" > "${json_file}.tmp" && mv "${json_file}.tmp" "$json_file"

  run "$MAW_BIN" handover --validate ws1
  [ "$status" -ne 0 ]
}

@test "maw migrate handover --to v3 --dry-run でプレビューが表示される（適用なし）" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --blocked-by "v2 string blocker"

  local before_version
  before_version="$(jq -r '.version' .maw/handovers/ws-ws1.json)"

  run "$MAW_BIN" migrate handover --to v3 ws1 --dry-run
  [ "$status" -eq 0 ]

  # dry-run なのでファイルは変更されない
  local after_version
  after_version="$(jq -r '.version' .maw/handovers/ws-ws1.json)"
  [ "$before_version" = "$after_version" ]
}

@test "maw migrate handover --to v3 --apply で v2→v3 変換が適用される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --blocked-by "v2 string blocker"

  "$MAW_BIN" migrate handover --to v3 ws1 --apply

  local json_file=".maw/handovers/ws-ws1.json"
  local version bl_type bl_desc bl_resolved
  version="$(jq -r '.version' "$json_file")"
  bl_type="$(jq -r '.blocked_by[0].type' "$json_file")"
  bl_desc="$(jq -r '.blocked_by[0].description' "$json_file")"
  bl_resolved="$(jq -r '.blocked_by[0].resolved' "$json_file")"

  [ "$version" = "3" ]
  [ "$bl_type" = "blocker" ]
  [ "$bl_desc" = "v2 string blocker" ]
  [ "$bl_resolved" = "false" ]
}

@test "maw migrate handover --to v3 --apply 後も takeover --format plan が動作する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --blocked-by "v2 string blocker"
  "$MAW_BIN" migrate handover --to v3 ws1 --apply

  run "$MAW_BIN" takeover ws1 --format plan
  [ "$status" -eq 0 ]

  local blockers_count
  blockers_count="$(echo "$output" | jq -r '.blockers_count')"
  [ "$blockers_count" -eq 1 ]
}

@test "maw migrate handover --to v3 は既存の v3 ファイルをスキップする" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  # v3 に手動設定
  local json_file=".maw/handovers/ws-ws1.json"
  jq '.version = 3' "$json_file" > "${json_file}.tmp" && mv "${json_file}.tmp" "$json_file"

  run "$MAW_BIN" migrate handover --to v3 ws1 --apply
  [ "$status" -eq 0 ]
  [[ "$output" =~ "migration not needed" ]]
}

# ===== v0.8.0: takeover priority_actions 強化 =====

@test "takeover --format plan の priority_actions は最小契約を満たす" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  echo "$output" | jq -e '
    (.priority_actions | type == "array") and
    ([.priority_actions[] |
      (has("priority_level") and (.priority_level | type == "number") and (.priority_level | floor == . and . >= 1 and . <= 3)) and
      (has("action") and (.action | type == "string")) and
      (has("description") and (.description | type == "string")) and
      (has("priority") and (.priority == "low" or .priority == "medium" or .priority == "high"))
    ] | all)
  ' >/dev/null
}

@test "verification_status=failed で priority_level 1 の verify アクションが生成される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --verification-status failed

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local p1_action
  p1_action="$(echo "$output" | jq -r '[.priority_actions[] | select(.priority_level == 1 and .action == "verify")] | first | .action')"
  [ "$p1_action" = "verify" ]
}

@test "type=blocker の blocked_by は priority_level 1 のアクションを生成する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 \
    --blocked-by-type blocker \
    --blocked-by-desc "critical blocker"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local p1_unblock
  p1_unblock="$(echo "$output" | jq -r '[.priority_actions[] | select(.priority_level == 1 and .action == "unblock")] | first | .blocker_type')"
  [ "$p1_unblock" = "blocker" ]
}

@test "type=dependency の blocked_by は priority_level 2 のアクションを生成する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 \
    --blocked-by-type dependency \
    --blocked-by-desc "waiting for library update"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local p2_unblock
  p2_unblock="$(echo "$output" | jq -r '[.priority_actions[] | select(.priority_level == 2 and .action == "unblock")] | first | .blocker_type')"
  [ "$p2_unblock" = "dependency" ]
}

@test "type=issue の blocked_by は priority_level 2 のアクションを生成し description に Issue が含まれる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 \
    --blocked-by-type issue \
    --blocked-by-desc "design approval needed"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local p2_desc
  p2_desc="$(echo "$output" | jq -r '[.priority_actions[] | select(.priority_level == 2 and .action == "unblock")] | first | .description')"
  [[ "$p2_desc" =~ "Issue" ]]
}

@test "type=blocker は type=dependency より優先順位が高い（priority_level 1 < 2）" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 \
    --blocked-by-type blocker \
    --blocked-by-desc "critical blocker"
  "$MAW_BIN" handover --workspace ws1 \
    --blocked-by-type dependency \
    --blocked-by-desc "dependency blocker"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local blocker_level dep_level
  blocker_level="$(echo "$output" | jq -r '[.priority_actions[] | select(.blocker_type == "blocker")] | first | .priority_level')"
  dep_level="$(echo "$output" | jq -r '[.priority_actions[] | select(.blocker_type == "dependency")] | first | .priority_level')"

  [ "$blocker_level" -eq 1 ]
  [ "$dep_level" -eq 2 ]
}

@test "v2 string blocked_by は priority_level 2 の unblock アクションにフォールバックする" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --blocked-by "v2 string blocker"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local p2_unblock_type
  p2_unblock_type="$(echo "$output" | jq -r '[.priority_actions[] | select(.priority_level == 2 and .action == "unblock")] | first | .blocker_type')"
  [ "$p2_unblock_type" = "unknown" ]
}

@test "takeover --format plan は同じ bundle で同じ plan を返す（idempotent）" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 \
    --blocked-by-type dependency \
    --blocked-by-desc "PR waiting" \
    --verification-status failed

  local output1 output2
  output1="$("$MAW_BIN" takeover ws1 --format plan)"
  output2="$("$MAW_BIN" takeover ws1 --format plan)"

  [ "$output1" = "$output2" ]
}

@test "--blocked-by-owner が指定された blocker は description に owner が含まれる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 \
    --blocked-by-type blocker \
    --blocked-by-desc "waiting for decision" \
    --blocked-by-owner nil

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local action_desc
  action_desc="$(echo "$output" | jq -r '[.priority_actions[] | select(.priority_level == 1 and .action == "unblock")] | first | .description')"
  [[ "$action_desc" =~ "nil" ]]
}

@test "verify アクションに commands フィールドが含まれる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 \
    --verification-status failed \
    --resume-command "npm test"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local has_commands cmd_val
  has_commands="$(echo "$output" | jq -r '[.priority_actions[] | select(.action == "verify")] | first | has("commands")')"
  cmd_val="$(echo "$output" | jq -r '[.priority_actions[] | select(.action == "verify")] | first | .commands[0]')"

  [ "$has_commands" = "true" ]
  [ "$cmd_val" = "npm test" ]
}

@test "next_steps は priority_level 3 の next_step アクションとして追加される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --next-step "PR をレビューする"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local p3_action p3_desc
  p3_action="$(echo "$output" | jq -r '[.priority_actions[] | select(.priority_level == 3 and .action == "next_step")] | first | .action')"
  p3_desc="$(echo "$output" | jq -r '[.priority_actions[] | select(.priority_level == 3 and .action == "next_step")] | first | .description')"

  [ "$p3_action" = "next_step" ]
  [ "$p3_desc" = "PR をレビューする" ]
}

# ===== v0.9.0: Canonical State v0 =====

@test "新規 handover JSON に id フィールドが含まれる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  local id
  id="$(jq -r '.id' .maw/handovers/ws-ws1.json)"
  [ "$id" != "null" ]
  [ -n "$id" ]
  [ "${#id}" -eq 16 ]
}

@test "新規 handover JSON に summary フィールドが空文字で含まれる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  local summary
  summary="$(jq -r '.summary' .maw/handovers/ws-ws1.json)"
  [ "$summary" = "" ]
}

@test "新規 handover JSON に evidence_refs フィールドが空配列で含まれる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  local er_type er_len
  er_type="$(jq -r '.evidence_refs | type' .maw/handovers/ws-ws1.json)"
  er_len="$(jq -r '.evidence_refs | length' .maw/handovers/ws-ws1.json)"
  [ "$er_type" = "array" ]
  [ "$er_len" -eq 0 ]
}

@test "maw handover --summary で summary が設定される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" handover --workspace ws1 --summary "認証モジュールのリファクタリング中。JWT移行完了、テスト待ち。"
  [ "$status" -eq 0 ]

  local summary
  summary="$(jq -r '.summary' .maw/handovers/ws-ws1.json)"
  [ "$summary" = "認証モジュールのリファクタリング中。JWT移行完了、テスト待ち。" ]
}

@test "maw handover --evidence-ref で evidence_refs 配列に追加される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" handover --workspace ws1 --evidence-ref "diff:HEAD~1"
  [ "$status" -eq 0 ]

  local ref len
  ref="$(jq -r '.evidence_refs[0]' .maw/handovers/ws-ws1.json)"
  len="$(jq '.evidence_refs | length' .maw/handovers/ws-ws1.json)"
  [ "$ref" = "diff:HEAD~1" ]
  [ "$len" -eq 1 ]
}

@test "maw handover --evidence-ref 複数指定で全て追加される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  run "$MAW_BIN" handover --workspace ws1 --evidence-ref "diff:HEAD~1" --evidence-ref "test:npm test"
  [ "$status" -eq 0 ]

  local len first second
  len="$(jq '.evidence_refs | length' .maw/handovers/ws-ws1.json)"
  first="$(jq -r '.evidence_refs[0]' .maw/handovers/ws-ws1.json)"
  second="$(jq -r '.evidence_refs[1]' .maw/handovers/ws-ws1.json)"
  [ "$len" -eq 2 ]
  [ "$first" = "diff:HEAD~1" ]
  [ "$second" = "test:npm test" ]
}

@test "maw takeover --format plan の出力に id/summary/evidence_refs が含まれる" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --summary "テスト中" --evidence-ref "diff:HEAD~1"

  local output
  output="$("$MAW_BIN" takeover ws1 --format plan)"

  local id summary er_len
  id="$(echo "$output" | jq -r '.id')"
  summary="$(echo "$output" | jq -r '.summary')"
  er_len="$(echo "$output" | jq '.evidence_refs | length')"

  [ -n "$id" ]
  [ "$id" != "null" ]
  [ "$summary" = "テスト中" ]
  [ "$er_len" -eq 1 ]
}

@test "maw takeover --format plan は id/summary/evidence_refs が欠けた bundle でも既定値で成功する" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  local json_file=".maw/handovers/ws-ws1.json"
  jq 'del(.id, .summary, .evidence_refs)' "$json_file" > "${json_file}.tmp" \
    && mv "${json_file}.tmp" "$json_file"

  run "$MAW_BIN" takeover ws1 --format plan
  [ "$status" -eq 0 ]

  local id summary er_len
  id="$(echo "$output" | jq -r '.id')"
  summary="$(echo "$output" | jq -r '.summary')"
  er_len="$(echo "$output" | jq '.evidence_refs | length')"

  [ "$id" = "" ]
  [ "$summary" = "" ]
  [ "$er_len" -eq 0 ]
}

@test "maw takeover --format prompt の出力に Summary セクションが含まれる（summary 非空の場合）" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  "$MAW_BIN" handover --workspace ws1 --summary "認証モジュールのリファクタリング中"

  run "$MAW_BIN" takeover ws1 --format prompt
  [ "$status" -eq 0 ]
  [[ "$output" =~ "## Summary" ]]
  [[ "$output" =~ "認証モジュールのリファクタリング中" ]]
}

@test "maw takeover --format prompt で summary が空の場合は Summary セクションが出力されない" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1
  # summary は "" のまま

  run "$MAW_BIN" takeover ws1 --format prompt
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "## Summary" ]]
}

@test "maw migrate handover --to v3 --apply 後に id/summary/evidence_refs が補完される" {
  "$MAW_BIN" init
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" handover --workspace ws1

  # v0.9.0 以前のファイルを模倣：id/summary/evidence_refs を削除
  local json_file=".maw/handovers/ws-ws1.json"
  jq 'del(.id) | del(.summary) | del(.evidence_refs)' "$json_file" > "${json_file}.tmp" \
    && mv "${json_file}.tmp" "$json_file"

  "$MAW_BIN" migrate handover --to v3 ws1 --apply

  local id summary er_type
  id="$(jq -r '.id' "$json_file")"
  summary="$(jq -r '.summary' "$json_file")"
  er_type="$(jq -r '.evidence_refs | type' "$json_file")"

  [ "$id" != "null" ]
  [ -n "$id" ]
  [ "$summary" = "" ]
  [ "$er_type" = "array" ]
}
