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
| `--from <branch>` | 分岐元ブランチ（明示指定時は最優先） | `origin/main`（`--from` 未指定時に fetch） |

### 使用例

```bash
maw spawn feature-auth
maw spawn feature-auth --agent claude
maw spawn feature-auth --issue 42
maw spawn feature-auth --agent claude --issue 42  # ブランチ: claude/feature-auth
maw spawn feature-auth --isolated                 # 独立した node_modules
maw spawn feature-auth --from develop             # origin/main ではなく develop を優先
```

### 動作

1. `--from <branch>` を指定した場合、そのブランチを分岐元として優先する
2. `--from` 未指定の場合、`origin/main` を fetch して最新を分岐元として使う
3. `origin/main` を fetch/resolve できない場合は失敗（フォールバックなし）
4. 指定ブランチ名で git worktree を作成し、`.maw-workspaces/<name>/` にチェックアウト
5. ecosystem に応じた symlink を作成（`--isolated` でスキップ）し、`state.json` にワークスペース情報を登録

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

引き継ぎドキュメントを生成・編集します。Markdown ファイルに加えて JSON サイドカーも出力します（v0.5.0 以降）。

### 概要

```bash
maw handover [--workspace <name>] [--scope full|summary|evidence] [--validate <name>] [edit options]
```

### オプション

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `--workspace <name>` | ワークスペース名を明示指定 | 現在の WS を自動検出 |
| `--scope <mode>` | 出力スコープを指定 | `full` |
| `--validate <name>` | handover JSON の整合性を検証（生成は行わない） | — |

### 編集オプション（v0.6.0 以降）

| オプション | 説明 |
|-----------|------|
| `--next-step <text>` | next_steps 配列に追加 |
| `--decision <text>` | decisions 配列に追加（タイムスタンプ付き） |
| `--risk <text>` | risks 配列に追加 |
| `--risk-severity <level>` | リスク重要度 (low\|medium\|high\|critical, デフォルト: medium) |
| `--resume-command <cmd>` | resume_commands 配列に追加 |
| `--verification-status <s>` | verification_status を更新 (pending\|passed\|failed\|skipped) |
| `--blocked-by <text>` | blocked_by 配列に追加（作業をブロックする要因を記録） |

### --scope モード

| モード | Markdown | JSON サイドカー | 説明 |
|--------|---------|----------------|------|
| `full` | 生成 | 生成 | 全セクション（デフォルト） |
| `summary` | 生成 | 生成 | ブランチ・diff stat・next_steps のみ（diff 本体は省略） |
| `evidence` | 生成 | **生成しない** | git log・変更ファイル・未コミット変更のみ |

### 出力先

```
.maw/handovers/ws-<name>.md    # Markdown（人間向け）
.maw/handovers/ws-<name>.json  # JSON（LLM / maw takeover 向け）※ scope=evidence 以外
```

### JSON サイドカースキーマ (v2)

```json
{
  "version": 2,
  "workspace": "feature-auth",
  "branch": "claude/feature-auth",
  "base_branch": "main",
  "agent": "claude",
  "issue": "42",
  "summary": "Add JWT authentication",
  "decisions": [
    {
      "topic": "Auth library",
      "decision": "jsonwebtoken を使用",
      "rationale": "Node.js エコシステムで最も広く使われている"
    }
  ],
  "risks": [
    {
      "description": "トークン有効期限の設定",
      "mitigation": "環境変数で設定可能にする"
    }
  ],
  "blocked_by": ["外部 API の仕様確定"],
  "verification_status": "pending",
  "diff_stat": "...",
  "diff": "...（4096バイト上限）",
  "log": ["abc1234 fix: auth bug"],
  "claims": { "src/auth.ts": { "workspace": "...", "agent": "...", "claimed_at": "...", "expires_at": null } },
  "state": "clean",
  "next_steps": [],
  "resume_commands": ["npm test", "npm run build"],
  "generated_at": "2026-02-24T10:00:00Z"
}
```

**state の値**: `clean`（変更なし）/ `dirty`（未コミット変更あり）/ `stash`（stash あり）

### 生成内容（Markdown）

- ワークスペース情報（ブランチ・エージェント・Issue）
- コミット履歴（`git log --oneline`）
- 変更ファイル（`git diff --name-status`）
- 未コミット変更（`git status --short`）
- claims 一覧（当該 WS のみ）
- 引き継ぎメモ（自由記述プレースホルダー）

---

## `maw takeover [<name>] [options]`

handover JSON bundle を読み込んでセッション再開プロンプトを出力します（v0.5.0 以降）。

### 概要

```bash
maw takeover [<name>] [--format md|json|prompt|plan]
```

### 引数

| 引数 | 説明 |
|------|------|
| `<name>` | ワークスペース名（省略時は自動検出） |

### オプション

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `--format <mode>` | 出力形式 | `prompt` |

### --format モード

| モード | 説明 |
|--------|------|
| `prompt` | エージェント向けセッション再開プロンプト（構造化テキスト） |
| `plan` | downstream automation / CI が利用できる readiness 契約 JSON を出力 ※ v0.6.0 以降 |
| `json` | JSON サイドカーをそのまま出力（`jq .` 整形済み） |
| `md` | Markdown handover ファイルをそのまま出力 |

### --format plan 公開契約 (v0.6.0 以降)

`plan` は公開 JSON 契約です。key 順は固定しませんが、以下の top-level key は必須です。

| key | type | 説明 |
|-----|------|------|
| `id` | string | handover bundle にない場合は `""` |
| `summary` | string | handover bundle にない場合は `""` |
| `evidence_refs` | array<string> | handover bundle にない場合は `[]` |
| `workspace` | string | ワークスペース名 |
| `branch` | string | 対象ブランチ名 |
| `verification_status` | string | 推奨値: `pending \| passed \| failed \| skipped`。未対応値も返却するが scoring では `unknown` と同等に 30 点相当で扱う |
| `state` | string | 推奨値: `clean \| dirty \| stash`。未対応値も返却するが scoring では `unknown` と同等に 50 点相当で扱う |
| `decisions_count` | integer >= 0 | decisions 件数 |
| `risks_count` | integer >= 0 | risks 件数 |
| `blockers_count` | integer >= 0 | `blocked_by` の総件数 |
| `blockers` | array<string> | `blocked_by` を説明文へ正規化した配列。最大 3 件 |
| `score` | integer | `0..100` |
| `category` | string | `ready \| caution \| blocked` |
| `priority_actions` | array<object> | 各要素は下記の最小契約を満たす |
| `resume_commands` | array<string> | 再開時に使うコマンド候補 |

### `priority_actions[*]` 最小契約

各 action object は以下を required とします。追加フィールド（例: `commands`, `blocker_type`）は許容されます。

| key | type | 説明 |
|-----|------|------|
| `priority_level` | `1 \| 2 \| 3` | `1` が最優先 |
| `action` | string | 実行種別 |
| `description` | string | 人が読む説明 |
| `priority` | `low \| medium \| high` | 表示上の優先度 |

### 後方互換

- bundle に `id` / `summary` / `evidence_refs` がなくても plan 生成は成功し、既定値 `""`, `""`, `[]` を使います
- `blocked_by` が v2 の文字列配列でも plan 生成は成功します
- `blocked_by` が object/string 混在でも plan 生成は成功します

### --format plan 出力例

```json
{
  "id": "ws-feature-auth-20260306",
  "summary": "認証フローの確認待ち",
  "evidence_refs": ["diff:HEAD~1"],
  "workspace": "feature-auth",
  "branch": "claude/feature-auth",
  "verification_status": "pending",
  "state": "clean",
  "decisions_count": 2,
  "risks_count": 0,
  "blockers_count": 0,
  "blockers": [],
  "score": 72,
  "category": "caution",
  "priority_actions": [
    {
      "priority_level": 2,
      "action": "verify",
      "description": "テストを実行してください",
      "priority": "medium",
      "commands": ["npm test", "npm run build"]
    },
    {
      "priority_level": 3,
      "action": "review",
      "description": "注意点を確認してください",
      "priority": "low"
    }
  ],
  "resume_commands": ["npm test", "npm run build"]
}
```

**スコアリング基準**:
- `verification_status` (40%): passed=100, skipped=50, pending=30, failed=0, unknown=30
- `state` (20%): clean=100, stash=60, dirty=40, unknown=50
- `blockers_count` (20%): 0=100, 1-2=50, 3+=0
- `risks` (20%): 各リスクで減点 (low=5, medium=10, high=20, critical=40)

**カテゴリ判定**:
- `ready` (80-100): 作業開始可能
- `caution` (50-79): 注意点あり
- `blocked` (0-49): ブロック済み

### 使用例

```bash
# エージェントとしてセッションを再開する
maw takeover feature-auth

# プラン情報を確認する
maw takeover feature-auth --format plan

# JSON を確認する
maw takeover feature-auth --format json

# Markdown を確認する
maw takeover feature-auth --format md
```

### 前提条件

`maw handover`（scope = `full` または `summary`）で JSON サイドカーが生成されていること。
JSON ファイルがない場合はエラーになります。

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

## `maw doctor [options]`

環境の整合性をチェックします。

### 概要

```bash
maw doctor [--fix] [--aggressive] [--json]
```

### オプション

| オプション | 説明 |
|-----------|------|
| `--fix` | 検出された問題を自動修復 |
| `--aggressive` | マージ済みブランチ・dangling worktree の削除チェック（`--fix` 時に確認プロンプト付きで削除実行） |
| `--json` | 結果を JSON 形式で出力（v2 スキーマ、v0.6.0 以降）。exit code は `--exit-code-mode` 契約に従う |

### チェック項目

| チェック | 説明 | `--fix` での対応 |
|---------|------|-----------------|
| Orphaned worktree | state に存在するが worktree がない | state から削除 |
| Orphaned state | worktree はあるが state にない | 案内のみ（`maw cleanup <ws>` を表示） |
| Symlink 整合性 | symlink が正しいパスを指しているか | symlink を再作成 |
| Lockfile hash | lockfile が更新されていないか | 警告のみ |
| Orphaned claim | 削除済み WS の claim が残っている | claim を削除 |
| Stale claim | TTL 期限切れの claim | claim を削除 |

### --aggressive モードの追加チェック項目

| チェック | 説明 | `--fix` での対応 |
|---------|------|-----------------|
| マージ済みブランチ | base ブランチにマージ済みのブランチ | 確認プロンプト付きで worktree・ブランチ削除 |
| Dangling worktree | git worktree prune で削除可能な worktree | git worktree prune 実行 |
| 空 handover ファイル | サイズが 0 の handover ファイル | 削除 |

### 出力例

```
[WARN] orphaned claim: src/old.ts (workspace: deleted-ws)
[WARN] stale claim: src/auth.ts (expired: 2026-02-20 09:00)
[OK] worktree integrity: OK
[OK] symlink integrity: OK
```

### --json 出力スキーマ (v2, v0.6.0 以降)

```json
{
  "version": 2,
  "format": "doctor",
  "timestamp": "2026-02-24T10:00:00Z",
  "maw_version": "0.6.0",
  "health_score": 85,
  "summary": {
    "total_checks": 6,
    "passed": 4,
    "failed": 1,
    "warnings": 1,
    "fixable": 1
  },
  "categories": {
    "worktree": {"status": "passed", "score": 100},
    "symlink": {"status": "warning", "score": 70},
    "lockfile": {"status": "passed", "score": 100},
    "git": {"status": "passed", "score": 100},
    "claims": {"status": "failed", "score": 0},
    "stale_claims": {"status": "warning", "score": 80}
  },
  "checks": [
    {
      "name": "worktree_integrity",
      "status": "passed",
      "severity": "none",
      "message": "All worktrees match state.json",
      "fixable": false,
      "category": "worktree"
    }
  ]
}
```

### `doctor --json` 公開契約

`doctor --json` は公開 JSON 契約です。key 順は固定しませんが、以下の top-level key は必須です。

| key | type | 説明 |
|-----|------|------|
| `version` | integer | 現在は `2` |
| `format` | string | 現在は `"doctor"` |
| `timestamp` | string | UTC timestamp |
| `maw_version` | string | `maw` のバージョン |
| `health_score` | integer | `0..100` |
| `summary` | object | 下記の required subkeys を持つ |
| `categories` | object | 下記 6 カテゴリを必須で持つ |
| `checks` | array<object> | 各 entry は下記の最小契約を満たす |

### `summary` required subkeys

| key | type |
|-----|------|
| `total_checks` | integer >= 0 |
| `passed` | integer >= 0 |
| `failed` | integer >= 0 |
| `warnings` | integer >= 0 |
| `fixable` | integer >= 0 |

### `categories` required keys

必須カテゴリは `worktree`, `symlink`, `lockfile`, `git`, `claims`, `stale_claims` です。各カテゴリ object は以下を required とします。

| key | type | 説明 |
|-----|------|------|
| `status` | `passed \| warning \| failed` | カテゴリ状態 |
| `score` | integer | `0..100` |

現在のスコア規約:
- `passed = 100`
- `failed = 0`
- `warning = 70`（`symlink`, `lockfile`, `git`）
- `warning = 80`（`stale_claims`）

### `checks[*]` 最小契約

各 check object は以下を required とします。

| key | type |
|-----|------|
| `name` | string |
| `status` | `passed \| warning \| failed` |
| `severity` | `none \| warning \| error` |
| `message` | string |
| `fixable` | boolean |
| `category` | `worktree \| symlink \| lockfile \| git \| claims \| stale_claims` |

### Exit code 契約

既定値は `simple` です。

| Mode | 問題なし | warning only | failed issues | invalid mode |
|------|----------|--------------|---------------|--------------|
| `simple` | 0 | 0 | 1 | 1 |
| `multi` | 0 | 2 | 1 | 1 |

---

## `maw migrate <json-file>`

handover JSON を v1 から v2 に移行します。

### 概要

```bash
maw migrate <json-file>
```

### 引数

| 引数 | 説明 |
|------|------|
| `<json-file>` | 移行対象の JSON ファイルパス |

### 動作

1. JSON ファイルの version を確認
2. version 1 の場合、version 2 に更新
3. 以下のフィールドを追加（空配列/デフォルト値で初期化）:
   - `decisions`: []
   - `risks`: []
   - `blocked_by`: []
   - `resume_commands`: []
   - `verification_status`: "pending"
4. 元の JSON ファイルを上書き

### 使用例

```bash
# handover JSON を v1 から v2 に移行
maw migrate .maw/handovers/ws-feature-auth.json

# 移行後の JSON を確認
cat .maw/handovers/ws-feature-auth.json | jq '.version'
# 出力: 2
```
