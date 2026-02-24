# 設定リファレンス（日本語）

## 設定ファイル一覧

| ファイル | 説明 | gitignore |
|---------|------|-----------|
| `.maw/config.json` | プロジェクト設定 | ✓ |
| `.maw/state.json` | ワークスペース状態 | ✓ |
| `.maw/claims.json` | ファイル排他宣言 | ✓ |
| `.maw/lockfile-hash` | lockfile の SHA-256 | ✓ |
| `.maw/handovers/ws-<name>.md` | 引き継ぎドキュメント | ✓ |

---

## `.maw/config.json`

`maw init` 時に生成されるプロジェクト設定ファイルです。

### スキーマ

```json
{
  "version": 1,
  "ecosystem": "nodejs",
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

### フィールド詳細

#### `version` (integer, 必須)

設定スキーマのバージョン。現在は常に `1`。

#### `ecosystem` (string, 必須) — v0.4.0 追加

プロジェクトの ecosystem。`maw init` 時に自動検出されます。

| 値 | 検出条件 | symlink デフォルト |
|---|---------|-----------------|
| `nodejs` | `package.json` が存在 | `["node_modules"]` |
| `python` | `pyproject.toml` または `requirements.txt` が存在 | `[]` |
| `rust` | `Cargo.toml` が存在 | `["target"]` |
| `go` | `go.mod` が存在 | `[]` |
| `generic` | 上記以外 | `[]` |

手動変更も可能です。

#### `packageManager` (string, optional)

Node.js ecosystem の場合にのみ使用されます。パッケージマネージャを指定します。

| 値 | 検出ファイル |
|---|------------|
| `yarn` | `yarn.lock` |
| `npm` | `package-lock.json` |
| `pnpm` | `pnpm-lock.yaml` |
| `bun` | `bun.lockb` |

#### `symlinkDirs` (string[], optional)

ワークスペース作成時に symlink を張るディレクトリ一覧。

```json
"symlinkDirs": ["node_modules", ".venv"]
```

各エントリはリポジトリルートからの相対パスです。
`maw spawn --isolated` を使うと symlink の代わりに独立インストールされます。

#### `copyFiles` (string[], optional)

ワークスペース作成時にコピーするファイル一覧。`.env` のような環境依存ファイルを各ワークスペースに複製する場合に使います。

```json
"copyFiles": [".env", ".envrc"]
```

#### `validationCommand` (string, optional)

品質チェックのためのコマンド。`maw doctor` や CI で利用できます。

```json
"validationCommand": "yarn lint && yarn compile && yarn test"
```

#### `github` (object, optional)

GitHub 連携情報。将来の機能拡張（Issue 連携等）で使用されます。

```json
"github": {
  "owner": "your-org",
  "repo": "your-project"
}
```

---

## `.maw/state.json`

すべてのワークスペースの状態を管理するファイルです。**直接編集は非推奨**（`maw doctor --fix` で修復可能）。

### スキーマ

```json
{
  "workspaces": {
    "feature-auth": {
      "name": "feature-auth",
      "branch": "claude/feature-auth",
      "agent": "claude",
      "issue": "42",
      "created": "2026-02-20",
      "path": "/path/to/.maw-workspaces/feature-auth"
    }
  }
}
```

### フィールド詳細

| フィールド | 型 | 説明 |
|-----------|---|------|
| `name` | string | ワークスペース名 |
| `branch` | string | git ブランチ名 |
| `agent` | string | エージェント種別（指定がなければ空文字） |
| `issue` | string | Issue 番号（指定がなければ空文字） |
| `created` | string | 作成日（YYYY-MM-DD） |
| `path` | string | worktree の絶対パス |

---

## `.maw/claims.json`

ファイル排他宣言を管理するファイルです。**直接編集は非推奨**。

### スキーマ

```json
{
  "claims": {
    "src/auth.ts": {
      "workspace": "feature-auth",
      "agent": "claude",
      "claimed_at": "2026-02-20T10:00:00Z",
      "expires_at": "2026-02-20T11:30:00Z"
    },
    "src/components/": {
      "workspace": "bugfix-login",
      "agent": "codex",
      "claimed_at": "2026-02-20T09:00:00Z",
      "expires_at": null
    }
  }
}
```

### フィールド詳細

| フィールド | 型 | 説明 |
|-----------|---|------|
| `workspace` | string | claim しているワークスペース名 |
| `agent` | string | claim したエージェント種別 |
| `claimed_at` | string | claim 日時（ISO 8601 UTC） |
| `expires_at` | string \| null | 有効期限（ISO 8601 UTC）。`null` は無期限 |

---

## `.maw/lockfile-hash`

lockfile（`yarn.lock` / `package-lock.json` / `pnpm-lock.yaml` 等）の SHA-256 ハッシュを保存します。

`maw doctor` が lockfile の変更を検出するために使用します。依存関係が更新されたのに symlink ワークスペースに反映されていない場合に警告します。

---

## `.maw/handovers/ws-<name>.md`

`maw handover` コマンドが生成する引き継ぎドキュメントです。Markdown 形式で人間可読です。

### 構成

```markdown
# Handover: feature-auth

Generated: 2026-02-20 10:30:00

## Workspace Info
- Branch: claude/feature-auth
- Agent: claude
- Issue: #42

## Recent Commits
（git log --oneline）

## Changed Files
（git diff --name-status）

## Uncommitted Changes
（git status --short）

## Claims
（当該 WS の claim 一覧）

## Notes
（自由記述プレースホルダー）
```

---

## 環境変数

maw は環境変数による設定上書きをサポートしていません（設計上の意図）。
すべての設定は `config.json` に記述してください。

---

## .gitignore との関係

`maw init` は `.gitignore` に以下を自動追加します:

```gitignore
# maw
.maw/
.maw-workspaces/
```

これらのディレクトリはリポジトリ固有のメタデータとワークスペース実体であるため、コミットするべきではありません。
