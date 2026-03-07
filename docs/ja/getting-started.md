# maw クイックスタート（日本語）

## 概要

maw (Multi-Agent Workspace) は、複数の AI エージェントが同一リポジトリで安全に並列作業するための CLI です。`git worktree` を土台にしますが、価値の中心はその上にある運用契約です。

- `maw claim` で編集衝突を事前に防ぐ
- `maw handover` で Markdown + JSON bundle を残す
- `maw takeover --format plan` で再開判断を `ready / caution / blocked` と `priority_actions` に正規化する
- `maw doctor --json` で CI / automation が読める健全性ゲートを提供する

## 前提条件

| ツール | バージョン | インストール |
|--------|-----------|-------------|
| git | 2.5 以上 | brew install git |
| jq | 1.6 以上 | brew install jq（macOS）/ sudo apt install jq（Linux） |
| bash | 3.2 以上 | 通常インストール済み |

## インストール

```bash
git clone https://github.com/yyyyyyy0/maw.git ~/.maw-cli
~/.maw-cli/install.sh
```

インストール確認:

```bash
maw --version
# => maw v0.9.0
```

## ステップ 1: プロジェクトを初期化する

```bash
cd your-project
maw init
```

初期化で作成されるもの:

```
your-project/
├── .maw/
│   ├── config.json       # プロジェクト設定
│   ├── state.json        # ワークスペース状態
│   ├── claims.json       # ファイル排他宣言
│   └── handovers/        # handover bundle
└── .maw-workspaces/      # git worktree 配置先
```

ecosystem（Node.js / Python / Rust / Go）は自動検出されます。`.gitignore` には `.maw/` と `.maw-workspaces/` が自動追加されます。

## ステップ 2: ワークスペースを作成する

```bash
# 基本
maw spawn feature-auth

# エージェント種別と Issue 番号を指定
maw spawn feature-auth --agent claude --issue 42

# 分岐元ブランチを明示
maw spawn feature-auth --agent claude --from develop
```

`--from` を省略すると、`maw spawn` は `origin/main` を fetch して最新を分岐元として使います。`origin/main` を fetch/resolve できない場合は失敗し、他ブランチへはフォールバックしません。

作成後、作業実体は `.maw-workspaces/feature-auth/` に配置されます。`git worktree` は隔離手段であり、運用の主役はここから先の contract です。

## ステップ 3: 現状確認と claim

```bash
maw status
maw claim src/auth.ts
```

ファイルを編集する前に **必ず** `maw claim` を実行します。これにより、他のエージェントが同じファイルや親ディレクトリを編集中なら事前に止められます。

TTL を付けることもできます:

```bash
maw claim src/auth.ts --ttl 90
```

## ステップ 4: handover bundle を生成する

まず baseline の handover bundle を生成します。

```bash
maw handover --workspace feature-auth
```

その後、次の再開に必要な structured fields を追記します。

```bash
maw handover --workspace feature-auth \
  --summary "JWT 移行は完了。検証待ち。" \
  --verification-status pending \
  --resume-command "bats tests/e2e_test.bats" \
  --evidence-ref "diff:HEAD~1" \
  --evidence-ref "test:bats tests/e2e_test.bats"
```

生成物:

- `.maw/handovers/ws-feature-auth.md`
  - 人間向けの handover view
- `.maw/handovers/ws-feature-auth.json`
  - `takeover` と automation が読む canonical bundle

JSON bundle には `summary`, `verification_status`, `resume_commands`, `evidence_refs`, `blocked_by`, `risks`, `decisions` などが入り、こちらが再開判断の正本です。

## ステップ 5: takeover plan を読む

`maw takeover --format plan` は handover bundle を `ready / caution / blocked` の再開計画に変換します。

```bash
maw takeover feature-auth --format plan | jq '{workspace, category, score, blockers, priority_actions}'
```

plan の主なフィールド:

- `category`: `ready | caution | blocked`
- `score`: 0-100 の readiness score
- `blockers`: 最大 3 件の blocker 要約
- `priority_actions`: 次にやるべきアクション一覧

補助ビュー:

```bash
maw takeover feature-auth --format json
maw takeover feature-auth --format md
maw takeover feature-auth --format prompt
```

`md` / `prompt` は人間や LLM への補助表示、`plan` / `json` は contract-centered output と考えるのが基本です。

## ステップ 6: doctor JSON で健全性を確認する

CI や automation では `doctor --json` を health gate として使います。

```bash
maw doctor --json --exit-code-mode multi | jq '{health_score, summary, categories}'
```

`--exit-code-mode multi` の exit code:

- `0`: 問題なし
- `2`: warning のみ
- `1`: failed issue あり

このモードを使うと、「警告だけを通知したい」「failed のときだけ止めたい」といった分岐を組みやすくなります。

## ステップ 7: マージする

```bash
maw merge feature-auth
```

必要に応じて:

```bash
maw merge feature-auth --base develop
maw merge feature-auth --dry-run
maw merge feature-auth --no-cleanup
```

`maw merge` を使うことで、claims と workspace lifecycle の後片付けが maw 管理下に保たれます。

## 典型的な daily workflow

```bash
# 1. 状況確認
maw status

# 2. ワークスペース作成
maw spawn my-feature --agent claude --issue 123

# 3. claim
maw claim src/target-file.ts

# 4. 実装...

# 5. handover bundle を更新
maw handover --workspace my-feature
maw handover --workspace my-feature \
  --summary "API 実装は完了。E2E 待ち。" \
  --verification-status pending \
  --resume-command "bats tests/e2e_test.bats" \
  --evidence-ref "diff:HEAD~1"

# 6. 再開 plan と health gate を確認
maw takeover my-feature --format plan
maw doctor --json --exit-code-mode multi

# 7. マージ
maw merge my-feature
```

## 次のドキュメント

- [コマンドリファレンス](commands.md) — 全コマンドの詳細オプションと出力契約
- [設定リファレンス](config.md) — config.json と設定ファイル
- [設計思想](concepts.md) — Workspace / claim / handover の背景
- [CI Integration](doctor-ci.md) — `maw doctor --json` を CI で使う方法
