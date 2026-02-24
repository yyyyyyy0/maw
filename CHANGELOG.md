# Changelog

## [Unreleased]

## [0.5.0] - 2026-02-24

### Added
- **Handover JSON bundle**: `maw handover` が `.maw/handovers/ws-<name>.json` サイドカーを生成
  - フィールド: `version`, `workspace`, `branch`, `base_branch`, `agent`, `issue`, `diff_stat`, `diff`（4KB上限）, `log`（配列）, `claims`（スナップショット）, `state`（clean/dirty/stash）, `next_steps`, `generated_at`
- **`maw handover --scope`**: 出力スコープを選択可能
  - `full`（デフォルト）: Markdown + JSON サイドカー両方
  - `summary`: Markdown + JSON 両方、diff 本体は省略
  - `evidence`: Markdown のみ（JSON サイドカーなし）
- **`maw takeover [<name>]`**: handover JSON bundle を読んでセッション再開プロンプトを出力
  - `--format prompt`（デフォルト）: エージェント向け構造化プロンプト
  - `--format json`: JSON サイドカーをそのまま出力
  - `--format md`: Markdown handover ファイルをそのまま出力
- テスト 14 ケース追加（合計 87 テスト）

### Changed
- `bin/maw` バージョンを `0.5.0` に更新

## [0.4.0] - 2026-02-24

### Added
- **Claim TTL**: `maw claim <file> --ttl <minutes>` で有効期限を設定可能
  - `claims.json` に `expires_at` (ISO 8601) フィールドを追加
  - `maw status` で期限切れ claim を赤色、TTL 付き claim を黄色で表示
  - `maw doctor` で期限切れ claim を検出 (Stale Claims セクション追加)
  - `maw doctor --fix` で期限切れ claim を自動削除
- **Ecosystem 汎用化**: `maw init` がプロジェクト種別を自動検出して適切なデフォルト設定を生成
  - 検出対象: nodejs / python / rust / go / generic
  - ecosystem 別 symlink デフォルト: nodejs=`node_modules`, python=`.venv`, rust/generic=なし, go=`vendor`(存在する場合)
  - `config.json` に `ecosystem` フィールドを追加 (`packageManager` は後方互換で保持)
- テスト 14 ケース追加 (合計 73 テスト)

### Changed
- `write_state()` / `write_claims()` をアトミック書き込みに変更 (tmpfile 経由の mv)
- `lib/core.sh` に `detect_ecosystem()`, `is_claim_expired()` ヘルパー追加
- `maw status` の Claims テーブルに EXPIRES カラムを追加

## [0.3.0] - 2026-02-24

### Added
- `maw merge [<name>]` コマンド: ワークスペースのブランチをベースブランチにマージ
  - `--base <branch>` オプションでマージ先ブランチを指定 (デフォルト: 現在のブランチ)
  - `--no-cleanup` オプションでマージ後にワークスペースを保持
  - `--dry-run` オプションで実際のマージを実行せず確認のみ
  - マージ前の事前チェック: 未コミット変更検出、ベースブランチ確認
  - マージ後に claims を自動削除 (orphan claim 防止)
  - デフォルトでワークスペース (worktree/ブランチ/handover) を自動クリーンアップ
- テスト 7 ケース追加 (合計 59 テスト)

## [0.2.0] - 2026-02-23

### Added
- `maw status` コマンド: ワークスペース状況とファイル排他情報を一括表示
  - 現在のワークスペースを `->` でハイライト
  - claims テーブル表示
- `maw claim <file|dir>` コマンド: ファイル/ディレクトリの排他宣言
  - 排他競合検出 (完全一致/ディレクトリ包含/逆包含)
  - 同一ワークスペースの再 claim は冪等に更新
  - `--workspace` オプションで明示指定可能
- `maw unclaim <file|dir>` コマンド: 排他宣言の解除
  - 所有者チェック (他 WS の claim はエラー)
  - `--force` オプションで強制解除
- `maw handover` コマンド: 引き継ぎドキュメント生成
  - ブランチ情報、コミット履歴、変更ファイル、未コミット変更、claims 一覧を出力
  - `.maw/handovers/ws-{name}.md` に保存
- `core.sh` にヘルパー関数追加: `read_claims`, `write_claims`, `detect_current_workspace`, `normalize_claim_path`
- テスト 23 ケース追加 (合計 52 テスト)

### Changed
- `maw cleanup` が claims を連動削除 (orphan claim 防止)
- `maw doctor` に claims 整合性チェック追加 (orphan claims 検出/`--fix` 自動修復)

## [0.1.0] - 2026-02-20

### Added
- `maw init` コマンド: プロジェクト初期化
  - `.maw/`, `.maw-workspaces/` ディレクトリ作成
  - パッケージマネージャ自動検出 (yarn/npm/pnpm/bun)
  - `.gitignore` 自動更新
  - lockfile hash 保存
- `maw spawn <name>` コマンド: ワークスペース作成
  - `--agent`, `--issue`, `--branch`, `--from` オプション
  - `--isolated` による独立依存環境
  - symlink による `node_modules` 共有
- `maw list` コマンド: ワークスペース一覧表示
- `maw cleanup` コマンド: ワークスペース削除
  - `--all`, `--merged`, `--dry-run` オプション
- `maw doctor` コマンド: 環境整合性チェック
  - orphaned worktree/state 検出
  - symlink 整合性チェック
  - lockfile hash 検証
  - `--fix` 自動修復
- GitHub Actions による bats テスト自動実行
- テスト 29 ケース

### Fixed
- symlink 経由の起動時にスクリプトパス解決が失敗する問題
- `maw list` のカラム表示崩れ

[0.4.0]: https://github.com/yyyyyyy0/maw/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/yyyyyyy0/maw/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/yyyyyyy0/maw/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/yyyyyyy0/maw/releases/tag/v0.1.0
