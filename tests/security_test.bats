#!/usr/bin/env bats

# セキュリティテスト - 入力バリデーションと攻撃対策

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

  # maw 初期化
  "$MAW_BIN" init
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

# ===== パストラバーサル攻撃対策 =====

@test "maw claim で ../ を含むパスは拒否される" {
  "$MAW_BIN" spawn ws1 --agent claude
  run "$MAW_BIN" claim "../etc/passwd" --workspace ws1
  [ "$status" -eq 1 ]
  [[ "$output" =~ "../" ]] || [[ "$output" =~ "パストラバーサル" ]]
}

@test "maw claim で絶対パスは拒否される" {
  "$MAW_BIN" spawn ws1 --agent claude
  run "$MAW_BIN" claim "/etc/passwd" --workspace ws1
  [ "$status" -eq 1 ]
  [[ "$output" =~ "'/' で始めることはできません" ]] || [[ "$output" =~ "相対パス" ]]
}

@test "maw claim で ../../etc/passwd は拒否される" {
  "$MAW_BIN" spawn ws1 --agent claude
  run "$MAW_BIN" claim "../../etc/passwd" --workspace ws1
  [ "$status" -eq 1 ]
  [[ "$output" =~ "../" ]] || [[ "$output" =~ "パストラバーサル" ]]
}

@test "maw unclaim で ../ を含むパスは拒否される" {
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" claim src/auth.ts --workspace ws1
  run "$MAW_BIN" unclaim "../etc/passwd" --workspace ws1
  [ "$status" -eq 1 ]
  [[ "$output" =~ "../" ]] || [[ "$output" =~ "パストラバーサル" ]]
}

# ===== ワークスペース名バリデーション =====

@test "maw spawn で予約語 init は拒否される" {
  run "$MAW_BIN" spawn init
  [ "$status" -eq 1 ]
  [[ "$output" =~ "予約語" ]]
}

@test "maw spawn で予約語 claim は拒否される" {
  run "$MAW_BIN" spawn claim
  [ "$status" -eq 1 ]
  [[ "$output" =~ "予約語" ]]
}

@test "maw spawn で予約語 test は拒否される" {
  run "$MAW_BIN" spawn test
  [ "$status" -eq 1 ]
  [[ "$output" =~ "予約語" ]]
}

@test "maw spawn で数字始まりの名前は拒否される" {
  run "$MAW_BIN" spawn 123workspace
  [ "$status" -eq 1 ]
  [[ "$output" =~ "英字で始める必要があります" ]]
}

@test "maw spawn でアンダースコア始まりの名前は拒否される" {
  run "$MAW_BIN" spawn _workspace
  [ "$status" -eq 1 ]
  [[ "$output" =~ "英字で始める必要があります" ]]
}

@test "maw spawn でハイフンを含む名前は拒否される" {
  run "$MAW_BIN" spawn my-workspace
  [ "$status" -eq 1 ]
  [[ "$output" =~ "英数字とアンダースコアのみ" ]]
}

@test "maw spawn で64文字以上の名前は拒否される" {
  run "$MAW_BIN" spawn aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  [ "$status" -eq 1 ]
  [[ "$output" =~ "1-63文字" ]]
}

@test "maw spawn で空の名前は拒否される" {
  run "$MAW_BIN" spawn ""
  [ "$status" -eq 1 ]
  [[ "$output" =~ "空" ]] || [[ "$output" =~ "指定してください" ]]
}

@test "maw spawn で有効なワークスペース名は受け入れられる" {
  run "$MAW_BIN" spawn my_workspace_123
  [ "$status" -eq 0 ]
  [ -d ".maw-workspaces/my_workspace_123" ]
}

@test "maw spawn で単一文字のワークスペース名は受け入れられる" {
  run "$MAW_BIN" spawn x
  [ "$status" -eq 0 ]
  [ -d ".maw-workspaces/x" ]
}

@test "maw spawn で63文字のワークスペース名は受け入れられる" {
  local name="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  [ "${#name}" -eq 63 ]
  run "$MAW_BIN" spawn "$name"
  [ "$status" -eq 0 ]
  [ -d ".maw-workspaces/$name" ]
}

# ===== nullバイト・制御文字対策 =====

# bash では文字列に null バイトが含まれている場合、そこで文字列が切り捨てられる
# このテストは bash の制限により実施困難なためスキップ
# @test "maw claim で nullバイトを含むパスは拒否される" {
#   "$MAW_BIN" spawn ws1 --agent claude
#   run "$MAW_BIN" claim $'src/auth\x00.ts' --workspace ws1
#   [ "$status" -eq 1 ]
#   [[ "$output" =~ "null" ]] || [[ "$output" =~ "バイト" ]]
# }

@test "maw claim で制御文字を含むパスは拒否される" {
  "$MAW_BIN" spawn ws1 --agent claude
  run "$MAW_BIN" claim $'src/auth\x01.ts' --workspace ws1
  [ "$status" -eq 1 ]
  [[ "$output" =~ "制御文字" ]]
}

# ===== 有効なパスのテスト =====

@test "maw claim で相対パスは受け入れられる" {
  "$MAW_BIN" spawn ws1 --agent claude
  run "$MAW_BIN" claim src/auth.ts --workspace ws1
  [ "$status" -eq 0 ]
  local claimed_ws
  claimed_ws="$(jq -r '.claims["src/auth.ts"].workspace' .maw/claims.json)"
  [ "$claimed_ws" = "ws1" ]
}

@test "maw claim で ./ を含むパスは正規化される" {
  "$MAW_BIN" spawn ws1 --agent claude
  run "$MAW_BIN" claim ./src/auth.ts --workspace ws1
  [ "$status" -eq 0 ]
  # 正規化されて ./ が除去されている
  local claimed_ws
  claimed_ws="$(jq -r '.claims["src/auth.ts"].workspace' .maw/claims.json)"
  [ "$claimed_ws" = "ws1" ]
}

@test "maw claim でディレクトリパスは受け入れられる" {
  "$MAW_BIN" spawn ws1 --agent claude
  run "$MAW_BIN" claim src/components/ --workspace ws1
  [ "$status" -eq 0 ]
  local claimed_ws
  claimed_ws="$(jq -r '.claims["src/components/"].workspace' .maw/claims.json)"
  [ "$claimed_ws" = "ws1" ]
}

# ===== 並行アクセス保護のテスト（基本） =====

@test "maw spawn で同じ名前のワークスペースは重複拒否される" {
  "$MAW_BIN" spawn ws1
  run "$MAW_BIN" spawn ws1
  [ "$status" -eq 1 ]
  [[ "$output" =~ "既に存在" ]]
}

@test "maw claim で他 WS の claim と競合すると拒否される" {
  "$MAW_BIN" spawn ws1 --agent claude
  "$MAW_BIN" spawn ws2 --agent codex
  "$MAW_BIN" claim src/auth.ts --workspace ws1
  run "$MAW_BIN" claim src/auth.ts --workspace ws2
  [ "$status" -eq 1 ]
  [[ "$output" =~ "排他競合" ]]
}

# ===== 絶対パスがルート外を参照する場合のテスト =====

@test "maw claim でルート外の絶対パスは拒否される" {
  "$MAW_BIN" spawn ws1 --agent claude
  run "$MAW_BIN" claim "/tmp/test" --workspace ws1
  [ "$status" -eq 1 ]
  [[ "$output" =~ "'/' で始める" ]] || [[ "$output" =~ "プロジェクトルート外" ]]
}

# ===== 特殊文字のテスト =====

@test "maw claim でスペースを含むパスは受け入れ可能（OS許容）" {
  "$MAW_BIN" spawn ws1 --agent claude
  mkdir -p "src dir"
  run "$MAW_BIN" claim "src dir/file.ts" --workspace ws1
  [ "$status" -eq 0 ]
}

@test "maw spawn で日本語を含むワークスペース名は拒否される（英数字のみ）" {
  run "$MAW_BIN" spawn ワークスペース
  [ "$status" -eq 1 ]
  [[ "$output" =~ "英字で始める必要があります" ]] || [[ "$output" =~ "英数字とアンダースコアのみ" ]]
}
