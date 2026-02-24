# コマンドリファレンス（日本語）

## グローバルオプション

```
maw [--version] [--help]
```

| オプション | 説明 |
|-----------|------|
| `--version` | バージョンを表示して終了 |
| `--help` | ヘルプを表示して終了 |

---

## `maw init`

プロジェクトを maw 用に初期化します。

### 概要

```bash
maw init
```

### 動作

1. git リポジトリ内であることを確認
2. `.maw/`、`.maw-workspaces/`、`.maw/handovers/` を作成
3. ecosystem を自動検出（nodejs / python / rust / go / generic）
4. パッケージマネージャを自動検出（nodejs の場合: yarn / npm / pnpm / bun）
5. `.gitignore` に `.maw/` と `.maw-workspaces/` を追加
6. `config.json`、`state.json`、`claims.json` を生成
7. lockfile の SHA-256 ハッシュを `.maw/lockfile-hash` に保存

### 生成されるファイル

- `.maw/config.json` — プロジェクト設定
- `.maw/state.json` — ワークスペース状態（初期は空）
- `.maw/claims.json` — ファイル排他宣言（初期は空）
- `.maw/lockfile-hash` — lockfile のハッシュ値

### 注意

- すでに `.maw/` が存在する場合は初期化済みエラー
- git リポジトリ外では実行不可

---

## `maw spawn <name> [options]`

新しいワークスペースを作成します。

### 概要

```bash
maw spawn <name> [--branch <name>] [--issue <number>] [--agent <name>]
                  [--isolated] [--from <branch>]
```

### 引数

| 引数 | 説明 |
|------|------|
| `<name>` | ワークスペース名（英数字・ハイフン推奨） |

### オプション

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `--branch <name>` | ブランチ名を直接指定 | `<name>` |
| `--issue <number>` | Issue 番号（ブランチ: `issue/<number>-<name>`） | — |
| `--agent <name>` | エージェント種別（ブランチ: `<agent>/<name>`） | — |
| `--isolated` | symlink ではなく独立した依存をインストール | false |
| `--from <branch>` | 分岐元ブランチ | 現在のブランチ |

### 使用例

```bash
maw spawn feature-auth
maw spawn feature-auth --agent claude
maw spawn feature-auth --issue 42
maw spawn feature-auth --agent claude --issue 42  # ブランチ: claude/feature-auth
maw spawn feature-auth --isolated                 # 独立した node_modules
maw spawn feature-auth --from develop             # develop から分岐
```

### 動作

1. 指定ブランチ名で git worktree を作成
2. `.maw-workspaces/<name>/` にチェックアウト
3. ecosystem に応じた symlink を作成（`--isolated` でスキップ）
4. `state.json` にワークスペース情報を登録

---

## `maw list`

全ワークスペースの一覧をテーブル表示します。

### 概要

```bash
maw list
```

### 出力例

```
NAME             BRANCH                         AGENT      ISSUE    CREATED
------------------------------------------------------------------------------------------
feature-auth     claude/feature-auth            claude     42       2026-02-20
bugfix-login     issue/99-bugfix-login          -          99       2026-02-20
```

---

## `maw status`

ワークスペース状況とファイル排他情報を一括表示します。

### 概要

```bash
maw status
```

### 出力例

```
=== Workspaces ===
     NAME             BRANCH                         AGENT      ISSUE    CREATED
  ------------------------------------------------------------------------------------------------
  -> feature-auth     claude/feature-auth            claude     42       2026-02-20
     bugfix-login     issue/99-bugfix-login          -          99       2026-02-20

=== Claims ===
  FILE                           WORKSPACE        AGENT      CLAIMED              EXPIRES
  -----------------------------------------------------------------------------------------
  src/auth.ts                    feature-auth     claude     2026-02-20 10:00     2026-02-20 11:30
```

### 表示仕様

- `->` は現在の作業ディレクトリに対応するワークスペース
- Claims の EXPIRES 列:
  - 有効期限なし: `-`
  - 有効期限あり（残り > 10 分）: 黄色で表示
  - 期限切れ: 赤色で表示

---

## `maw claim <path> [options]`

ファイルまたはディレクトリの排他宣言を行います。

### 概要

```bash
maw claim <path> [--workspace <name>] [--ttl <minutes>]
```

### 引数

| 引数 | 説明 |
|------|------|
| `<path>` | 排他宣言するファイルまたはディレクトリのパス |

### オプション

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `--workspace <name>` | ワークスペース名を明示指定 | 現在の WS を自動検出 |
| `--ttl <minutes>` | 有効期限（分）。省略時は無期限 | なし |

### 使用例

```bash
maw claim src/auth.ts
maw claim src/components/ --workspace ws1
maw claim src/auth.ts --ttl 90      # 90 分後に期限切れ
```

### 排他チェックルール

| 状況 | 結果 |
|------|------|
| 他 WS が同一ファイルを claim 済み | エラー |
| 他 WS が親ディレクトリを claim 済み | エラー |
| 他 WS が子ファイルを claim 済み（ディレクトリ claim 時） | エラー |
| 同一 WS が再 claim | 冪等（更新） |
| 期限切れ claim への上書き claim | 成功 |

---

## `maw unclaim <path> [options]`

排他宣言を解除します。

### 概要

```bash
maw unclaim <path> [--workspace <name>] [--force]
```

### 引数

| 引数 | 説明 |
|------|------|
| `<path>` | 解除するファイルまたはディレクトリのパス |

### オプション

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `--workspace <name>` | ワークスペース名を明示指定 | 現在の WS を自動検出 |
| `--force` | 他 WS の claim も強制解除 | false |

### 使用例

```bash
maw unclaim src/auth.ts               # 自分の claim を解除
maw unclaim src/auth.ts --force       # 他 WS の claim も強制解除
```

---

## `maw handover [options]`

引き継ぎドキュメントを生成します。

### 概要

```bash
maw handover [--workspace <name>]
```

### オプション

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `--workspace <name>` | ワークスペース名を明示指定 | 現在の WS を自動検出 |

### 出力先

`.maw/handovers/ws-<name>.md`

### 生成内容

- ワークスペース情報（ブランチ・エージェント・Issue）
- コミット履歴（`git log --oneline` 最新 20 件）
- 変更ファイル（`git diff --name-status`）
- 未コミット変更（`git status --short`）
- claims 一覧（当該 WS のみ）
- 引き継ぎメモ（自由記述プレースホルダー）

---

## `maw merge <name> [options]`

ワークスペースのブランチをマージします。

### 概要

```bash
maw merge <name> [--base <branch>] [--no-cleanup] [--dry-run]
```

### 引数

| 引数 | 説明 |
|------|------|
| `<name>` | マージするワークスペース名 |

### オプション

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `--base <branch>` | マージ先ブランチ | `main` |
| `--no-cleanup` | マージ後にワークスペースを削除しない | false（削除する） |
| `--dry-run` | 実際にはマージせず確認のみ | false |

### 使用例

```bash
maw merge feature-auth               # main へマージ & cleanup
maw merge feature-auth --base develop
maw merge feature-auth --no-cleanup  # マージ後も WS を残す
maw merge feature-auth --dry-run     # 確認のみ
```

### 動作

1. 対象 WS の未コミット変更を確認
2. マージ先ブランチへ `git merge --no-ff`
3. マージ成功後、当該 WS の claims を自動削除
4. `--no-cleanup` なければ worktree・ブランチ・handover を削除
5. `state.json` から WS を削除

---

## `maw cleanup [<name>|--all|--merged] [--dry-run]`

ワークスペースを削除します。

### 概要

```bash
maw cleanup [<name>] [--all] [--merged] [--dry-run]
```

### 引数・オプション

| 指定 | 説明 |
|------|------|
| `<name>` | 特定のワークスペースを削除 |
| `--all` | 全ワークスペースを削除 |
| `--merged` | マージ済みのワークスペースのみ削除 |
| `--dry-run` | 削除対象の確認のみ（実際には削除しない） |

### 使用例

```bash
maw cleanup feature-auth
maw cleanup --all
maw cleanup --merged
maw cleanup --all --dry-run
```

### 削除対象

- git worktree（`.maw-workspaces/<name>/`）
- ブランチ（マージ済みの場合のみ）
- handover ファイル（`.maw/handovers/ws-<name>.md`）
- claims（当該 WS 分）
- `state.json` のエントリ

---

## `maw doctor [--fix]`

環境の整合性をチェックします。

### 概要

```bash
maw doctor [--fix]
```

### オプション

| オプション | 説明 |
|-----------|------|
| `--fix` | 検出された問題を自動修復 |

### チェック項目

| チェック | 説明 | `--fix` での対応 |
|---------|------|-----------------|
| Orphaned worktree | state に存在するが worktree がない | state から削除 |
| Orphaned state | worktree はあるが state にない | state に追加 |
| Symlink 整合性 | symlink が正しいパスを指しているか | symlink を再作成 |
| Lockfile hash | lockfile が更新されていないか | 警告のみ |
| Orphaned claim | 削除済み WS の claim が残っている | claim を削除 |
| Stale claim | TTL 期限切れの claim | claim を削除 |

### 出力例

```
[WARN] orphaned claim: src/old.ts (workspace: deleted-ws)
[WARN] stale claim: src/auth.ts (expired: 2026-02-20 09:00)
[OK] worktree integrity: OK
[OK] symlink integrity: OK
```
