# maw

**Multi-Agent Workspace manager** - lightweight parallel workspaces for AI coding agents

マルチエージェント開発（Claude Code, Codex 等）で git worktree を活用し、並列作業を効率化する CLI ツールです。

## 解決する課題

| 課題 | maw の解決策 |
|---|---|
| コンテキスト共有が困難 | `.maw/` ディレクトリで進捗・排他情報を共有 |
| ディスク消費 | `node_modules` 等を symlink で共有 |
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

# 一覧表示
maw list

# 環境チェック
maw doctor

# クリーンアップ
maw cleanup feature-auth
```

## コマンド

### `maw init`

プロジェクトを maw 用に初期化します。

- `.maw/` と `.maw-workspaces/` ディレクトリを作成
- lockfile からパッケージマネージャを自動検出
- `.gitignore` に必要なエントリを追加

### `maw spawn <name> [options]`

新しいワークスペースを作成します。

```bash
maw spawn feature-auth                          # 基本
maw spawn feature-auth --agent claude            # エージェント指定
maw spawn feature-auth --issue 42                # Issue 紐付け
maw spawn feature-auth --agent claude --issue 42 # 両方指定
maw spawn feature-auth --isolated                # 独立依存環境
maw spawn feature-auth --from develop            # 分岐元ブランチ指定
```

**オプション**:

| オプション | 説明 |
|---|---|
| `--branch <name>` | ブランチ名を直接指定 |
| `--issue <number>` | Issue 番号を紐付け (`issue/{number}-{name}`) |
| `--agent <name>` | エージェント種別 (`{agent}/{name}`) |
| `--isolated` | symlink ではなく独立した依存をインストール |
| `--from <branch>` | 分岐元ブランチ (デフォルト: 現在のブランチ) |

### `maw list`

全ワークスペースの一覧をテーブル表示します。

```
NAME             BRANCH                         AGENT      ISSUE    CREATED
------------------------------------------------------------------------------------------
feature-auth     claude/feature-auth            claude     42       2026-02-20
bugfix-login     issue/99-bugfix-login          -          99       2026-02-20
```

### `maw cleanup [<name>|--all|--merged] [--dry-run]`

ワークスペースを削除します。

```bash
maw cleanup feature-auth  # 特定のワークスペース
maw cleanup --all          # 全ワークスペース
maw cleanup --merged       # マージ済みのみ
maw cleanup --all --dry-run  # 削除対象を確認のみ
```

### `maw doctor [--fix]`

環境の整合性をチェックします。

- orphaned worktree の検出
- symlink の整合性チェック
- lockfile hash の一致確認
- `--fix` で自動修復

## プロジェクト構成

```
project/
├── .maw/                         # メタデータ (gitignored)
│   ├── config.json               # プロジェクト設定
│   ├── state.json                # ワークスペース状態
│   ├── claims.json               # ファイル排他宣言
│   └── lockfile-hash             # lockfile の SHA-256
├── .maw-workspaces/              # worktree 配置先 (gitignored)
│   ├── agent-a/
│   │   ├── node_modules -> ../../node_modules  # symlink
│   │   └── src/ ...
│   └── agent-b/
│       ├── node_modules -> ../../node_modules  # symlink
│       └── src/ ...
├── node_modules/                 # 実体 (唯一)
└── src/ ...
```

## config.json

```json
{
  "version": 1,
  "packageManager": "yarn",
  "symlinkDirs": ["node_modules"],
  "copyFiles": [".env", ".envrc"],
  "validationCommand": "yarn lint && yarn compile && yarn test",
  "github": {
    "owner": "your-org",
    "repo": "your-project"
  }
}
```

## 設計方針

- **bash スクリプト**: 追加ランタイム不要
- **依存は git + jq のみ**: 最小限の前提条件
- **macOS + Linux 対応**: POSIX 互換重視
- **パッケージマネージャ自動検出**: yarn / npm / pnpm / bun

## ロードマップ

- [x] Phase 1: 基盤 (worktree + symlink + CLI)
- [ ] Phase 2: コンテキスト共有 (claim, handover, status)
- [ ] Phase 3: マージとライフサイクル
- [ ] Phase 4: 拡張 (補完, CoW clone, 多言語対応)

## ライセンス

MIT
