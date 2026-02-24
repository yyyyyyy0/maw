# maw クイックスタート（日本語）

## 概要

maw (Multi-Agent Workspace) は、複数の AI エージェントが同一リポジトリで並列作業するための CLI ツールです。
git worktree を活用して独立したワークスペースを作成し、ファイル排他宣言・引き継ぎドキュメント生成・ブランチマージを一元管理します。

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
# => maw version 0.5.1
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
│   └── handovers/        # 引き継ぎドキュメント
└── .maw-workspaces/      # worktree 配置先
```

ecosystem（Node.js / Python / Rust / Go）は自動検出されます。
`.gitignore` に `.maw/` と `.maw-workspaces/` が自動追加されます。

## ステップ 2: ワークスペースを作成する

```bash
# 基本的な作成
maw spawn feature-auth

# エージェント種別と Issue 番号を指定
maw spawn feature-auth --agent claude --issue 42

# 分岐元ブランチを指定
maw spawn feature-auth --agent claude --from develop
```

作成後、`.maw-workspaces/feature-auth/` に worktree が展開されます。
Node.js プロジェクトでは `node_modules` が symlink で共有されます（ディスク節約）。

## ステップ 3: 現状を確認する

```bash
maw status
```

出力例:

```
=== Workspaces ===
     NAME             BRANCH                    AGENT    ISSUE   CREATED
  -----------------------------------------------------------------------
  -> feature-auth     claude/feature-auth       claude   42      2026-02-24

=== Claims ===
  FILE                     WORKSPACE       AGENT    CLAIMED       EXPIRES
  -----------------------------------------------------------------------
  （なし）
```

`->` は現在の作業ディレクトリに対応するワークスペースです。

## ステップ 4: ファイルを排他宣言する

ファイルを編集する前に **必ず** `maw claim` で排他宣言します。これにより他のエージェントとの競合を防ぎます。

```bash
# ファイルを claim
maw claim src/auth.ts

# ディレクトリごと claim
maw claim src/components/

# TTL（有効期限）付きで claim（90 分後に自動失効）
maw claim src/auth.ts --ttl 90
```

他のワークスペースがすでに claim 済みの場合はエラーになります:

```
✗ src/auth.ts は feature-login (agent: claude) が claim 済みです
```

## ステップ 5: 作業・実装

ワークスペースの worktree ディレクトリ（`.maw-workspaces/feature-auth/`）内で通常どおり作業します。

完了したら:

```bash
maw unclaim src/auth.ts  # claim を解除
```

## ステップ 6: 引き継ぎドキュメントを生成する

作業完了後、次のエージェントや人間への引き継ぎ情報を生成します:

```bash
maw handover
```

`.maw/handovers/ws-feature-auth.md` が生成されます。内容:

- ブランチ情報・エージェント・Issue 番号
- コミット履歴（最新 20 件）
- 変更ファイル一覧
- 未コミット変更
- claims 状態
- 引き継ぎメモ（自由記述プレースホルダー）

## ステップ 7: セッションを引き継ぐ（takeover）

別のエージェントが作業を引き継ぐ場合、handover bundle を読み込んでセッション再開プロンプトを生成します:

```bash
maw takeover feature-auth
```

出力されるプロンプトには以下が含まれます:
- ブランチ情報・エージェント・Issue 番号
- 作業状態（clean/dirty/stash）
- アクティブな claims 一覧
- コミット履歴・変更ファイル
- next_steps（引き継ぎメモ）

フォーマットオプション:
```bash
maw takeover feature-auth --format json   # JSON を確認
maw takeover feature-auth --format md     # Markdown を確認
```

## ステップ 8: ブランチをマージする

```bash
# main ブランチへマージ（自動 cleanup 付き）
maw merge feature-auth

# マージ先ブランチを指定
maw merge feature-auth --base develop

# マージ後もワークスペースを残す
maw merge feature-auth --no-cleanup

# ドライラン（実際にはマージしない）
maw merge feature-auth --dry-run
```

マージ後、当該ワークスペースの claims が自動削除されます。

## ステップ 9: クリーンアップ

```bash
maw cleanup feature-auth        # 特定 WS を削除
maw cleanup --merged            # マージ済み WS をすべて削除
maw cleanup --all               # 全 WS を削除
maw cleanup --all --dry-run     # 削除対象の確認のみ
```

## 環境チェック

```bash
maw doctor       # 問題を検出
maw doctor --fix # 自動修復
```

doctor が確認する項目:

- orphaned worktree（state に存在するが worktree がない）
- orphaned symlink
- lockfile の変更（依存関係の更新漏れ）
- orphaned claim（ワークスペースが削除されたのに claim が残っている）
- 期限切れ claim

## 典型的なエージェントワークフロー

```bash
# 1. 状況確認
maw status

# 2. ワークスペース作成（初回のみ）
maw spawn my-feature --agent claude --issue 123

# 3. 編集前に claim
maw claim src/target-file.ts

# 4. 実装...

# 5. 引き継ぎ
maw handover

# 6. マージ & cleanup
maw merge my-feature
```

## 次のステップ

- [コマンドリファレンス](commands.md) — 全コマンドの詳細オプション
- [設定リファレンス](config.md) — config.json・設定ファイルの詳細
- [設計思想](concepts.md) — WS / claim / handover の設計思想
