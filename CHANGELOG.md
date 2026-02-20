# Changelog

## [Unreleased]

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
