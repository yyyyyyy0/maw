# maw

**Multi-Agent Workspace manager** - lightweight parallel workspaces for AI coding agents

マルチエージェント開発（Claude Code, Codex 等）で git worktree を活用し、並列作業を効率化する CLI ツールです。

## 解決する課題

| 課題 | maw の解決策 |
|---|---|
| ファイル競合 | `maw claim` で編集前に排他宣言・競合を事前防止 |
| コンテキスト断絶 | `maw handover` でセッション間の引き継ぎを自動生成 |
| ディスク消費 | `node_modules` 等を symlink で全 WS が共有 |
| 管理が煩雑 | worktree のライフサイクルを統合管理 |

## インストール

```bash
git clone https://github.com/yyyyyyy0/maw.git ~/.maw-cli
~/.maw-cli/install.sh
```

**必須ツール**: `git`, `jq`

```bash
# macOS
brew install jq

# Linux (Debian/Ubuntu)
sudo apt install jq
```

## クイックスタート

```bash
# プロジェクトを初期化
cd your-project
maw init

# ワークスペースを作成
maw spawn feature-auth --agent claude --issue 42

# 状況確認
maw status

# ファイルを排他宣言してから編集
maw claim src/auth.ts

# 引き継ぎ → マージ → クリーンアップ
maw handover
maw merge feature-auth
```

## コマンド一覧

| コマンド | 説明 |
|---------|------|
| `maw init` | プロジェクトを初期化 |
| `maw spawn <name>` | ワークスペースを作成 |
| `maw list` | ワークスペース一覧を表示 |
| `maw status` | ワークスペース状況と claims を表示 |
| `maw claim <path>` | ファイル/ディレクトリを排他宣言 |
| `maw unclaim <path>` | 排他宣言を解除 |
| `maw handover` | 引き継ぎドキュメントを生成 |
| `maw merge <name>` | ブランチをマージ |
| `maw cleanup` | ワークスペースを削除 |
| `maw doctor` | 環境の整合性チェック |

## ドキュメント

| ドキュメント | 説明 |
|------------|------|
| [クイックスタート（日本語）](docs/ja/getting-started.md) | インストールから基本ワークフローまで |
| [コマンドリファレンス（日本語）](docs/ja/commands.md) | 全コマンドの詳細オプション |
| [設定リファレンス（日本語）](docs/ja/config.md) | config.json・設定ファイルの詳細 |
| [設計思想（日本語）](docs/ja/concepts.md) | WS / claim / handover の設計思想 |
| [Quick Start (English)](docs/en/getting-started.md) | Installation and basic workflow |
| [Command Reference (English)](docs/en/commands.md) | All commands with options |
| [Configuration Reference (English)](docs/en/config.md) | config.json and settings |
| [Concepts (English)](docs/en/concepts.md) | WS / claim / handover design |

## エージェント向け

maw を AI エージェントとして使用する場合:

- `SKILL.md` — maw を使うための Claude Code スキル定義（R-SKILL-SCHEMA-001 準拠）
- `AGENTS.md` — コアオペレーティングルール
- `AGENTS.extensions.md` — maw Workspace ルール（R-MAW-*）

## ライセンス

MIT
