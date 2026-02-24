# 設計思想・概念（日本語）

## なぜ maw が必要か

複数の AI エージェントが同一リポジトリで並列作業する場合、以下の問題が発生します:

1. **ファイル競合**: 2 つのエージェントが同じファイルを同時編集する
2. **コンテキスト断絶**: あるエージェントの作業進捗を別のエージェントが知らない
3. **ライフサイクル管理**: worktree の作成・削除・マージが散漫になる

maw はこれらを **作業単位（Workspace）の管理**・**衝突制御（Claim）**・**引き継ぎ（Handover）** の 3 要素で解決します。

---

## Workspace（ワークスペース）

### 概念

Workspace は **独立した作業単位** です。git worktree として実装されており、各エージェントが独自のブランチを持ちながら依存関係（`node_modules` 等）を共有できます。

```
リポジトリルート/
├── .maw-workspaces/
│   ├── feature-auth/     <- agent-A の作業スペース (git worktree)
│   │   ├── src/          (実体: 独立したファイル)
│   │   └── node_modules  -> ../../node_modules  (symlink: 共有)
│   └── bugfix-login/     <- agent-B の作業スペース (git worktree)
│       ├── src/          (実体: 独立したファイル)
│       └── node_modules  -> ../../node_modules  (symlink: 共有)
└── node_modules/         <- 唯一の実体（全 WS で共有）
```

### 設計原則

- **1 エージェント = 1 Workspace**: 並列エージェントは必ず別々の WS を使う
- **ブランチ分離**: 各 WS は独立したブランチで作業する
- **依存共有**: `node_modules` 等の大きなディレクトリは symlink で共有してディスクを節約する
- **メタデータ中央集約**: `.maw/` ディレクトリがすべての WS の状態を管理する

### ライフサイクル

```
maw spawn  →  作業  →  maw handover  →  maw merge  →  maw cleanup
   ↑                                                        |
   └────────────────────────────────────────────────────────┘
               （必要なら新 WS を作成）
```

---

## Claim（ファイル排他宣言）

### 概念

Claim は **「このファイルは私が作業中」** という宣言です。AGENT.md の R-COLLAB-001「並列作業では共有ファイル編集前に競合リスクを確認する」の具体的な実装手段です。

### なぜ git の仕組みだけでは不十分か

git はマージ時に競合を検出しますが、**作業中の競合をリアルタイムで防げません**。A と B が同じファイルを並列編集し、後でマージしようとして初めて競合が発覚します。maw の Claim は **作業開始前**に競合を検出します。

### Claim の競合チェックルール

```
ファイル F の編集前に maw claim F を実行する

チェック 1: F が他 WS に claim 済み → エラー
チェック 2: F の親ディレクトリが他 WS に claim 済み → エラー
チェック 3: F がディレクトリで、F 配下が他 WS に claim 済み → エラー
チェック 4: 同一 WS の再 claim → 冪等（更新）
チェック 5: 期限切れ claim への上書き → 成功
```

### TTL（有効期限）

Claim には任意で有効期限（TTL）を設定できます（v0.4.0 以降）。

```bash
maw claim src/auth.ts --ttl 90   # 90 分後に自動失効
```

- TTL を設定すると `expires_at` フィールドが記録される
- 期限切れ claim は `maw doctor --fix` で自動削除できる
- 期限切れ claim には後続エージェントが上書き claim できる

TTL の目的:

1. **デッドエージェント対策**: クラッシュしたエージェントの claim が永続しないようにする
2. **ガード期間の明示**: 「あと N 分は触らないでほしい」という意図を伝える

### Claim のスコープ

| スコープ | 例 | 説明 |
|---------|---|------|
| ファイル | `src/auth.ts` | 単一ファイルの排他 |
| ディレクトリ | `src/components/` | ディレクトリ配下すべての排他 |

ディレクトリ claim は「この機能領域全体を作業中」という粗粒度の宣言に適しています。

---

## Handover（引き継ぎ）

### 概念

Handover は **作業の引き継ぎパッケージ** です。あるエージェントが作業を中断・完了した際に、次のエージェント（または人間）が同じコンテキストで作業を再開できるようにする情報束です。

### 設計の背景

AI エージェントはセッションを超えてコンテキストを保持できません。また、エージェントAの作業成果をエージェントBに「口頭で伝える」機能もありません。Handover はこのギャップを埋めます。

### 生成される情報

```markdown
# Handover: feature-auth

## Workspace Info
（ブランチ・エージェント・Issue）

## Recent Commits
（git log --oneline）

## Changed Files
（git diff --name-status）

## Uncommitted Changes
（git status --short）

## Claims
（当該 WS の claim 一覧）

## Notes
（引き継ぎメモ）
```

### Handover の使い方パターン

**パターン A: エージェント交代**
```
agent-A: maw handover  → .maw/handovers/ws-feature.md を生成
agent-B: .maw/handovers/ws-feature.md を読んで作業を継続
```

**パターン B: 人間へのレポート**
```
agent: maw handover  → .maw/handovers/ws-feature.md を生成
human: ファイルを読んで進捗を確認
```

**パターン C: マージ前の記録**
```
agent: maw handover  → 引き継ぎ記録を残す
agent: maw merge feature  → ブランチをマージ
```

---

## Ecosystem 汎用化（v0.4.0）

maw は当初 Node.js プロジェクト向けに設計されましたが、v0.4.0 で各エコシステムに対応しました。

### Ecosystem 検出

`maw init` 時にリポジトリルートのファイルを検査して ecosystem を決定します:

| 検出ファイル | ecosystem |
|------------|-----------|
| `package.json` | `nodejs` |
| `pyproject.toml` / `requirements.txt` | `python` |
| `Cargo.toml` | `rust` |
| `go.mod` | `go` |
| （上記以外） | `generic` |

### Symlink デフォルト

ecosystem ごとに symlink するディレクトリのデフォルトが異なります:

| ecosystem | デフォルト symlink |
|----------|------------------|
| `nodejs` | `node_modules` |
| `rust` | `target` |
| `python` / `go` / `generic` | なし |

`config.json` の `symlinkDirs` で手動上書きが可能です。

---

## アトミック書き込み

`state.json` と `claims.json` はアトミック書き込み（`mktemp` + `mv`）で更新されます。これにより:

- 書き込み中にクラッシュしてもファイルが壊れない
- 別プロセスが中途半端なファイルを読み込まない

この実装は並列エージェントが同時に状態を更新する場合の安全性を高めます。ただし、厳密なロック機構は持たないため、**同時書き込みのリスクがある操作は Claim で事前に宣言**することが重要です。

---

## maw と R-COLLAB-001

AGENTS.md の R-COLLAB-001 は:

> 「並列作業では共有ファイル編集前に競合リスクを確認する（MUST）」

と定義しています。maw はこのルールの **具体的な実装基盤** です:

- `maw claim` = 競合リスクの確認と宣言
- `maw status` = 現在の競合状況の確認
- `maw handover` = 作業の引き継ぎ記録
- `maw merge` = 統制されたブランチ統合

エージェントは `maw claim` なしに共有ファイルを編集してはなりません（R-MAW-CLAIM-001）。

---

## 設計方針

### bash のみ・依存最小

追加ランタイム（Node.js, Python 等）は不要です。bash と `git` と `jq` だけで動作します。これにより:

- どんな CI/CD 環境でも動く
- インストールが簡単
- スクリプトが透明で読める

### macOS + Linux 両対応

bash の portable 記法と `date` コマンドの macOS/GNU 両対応実装（TZ=UTC）により、主要プラットフォームで動作します。

### 冪等性

すべての操作は可能な限り冪等です。同じコマンドを 2 回実行しても安全です。
