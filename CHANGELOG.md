# Changelog

## [0.9.0] - 2026-02-26

### Added
- **Canonical State v0 最小スキーマ**: handover JSON に `id`/`summary`/`evidence_refs` フィールドを追加
  - 新規生成時に `id`（`workspace:generated_at` の sha256/md5 ハッシュ先頭16文字）を自動付与
  - 新規生成時に `summary: ""` および `evidence_refs: []` を初期化
- **`--summary` オプション**: `maw handover --summary <text>` でハンドオーバーの要約を記録
- **`--evidence-ref` オプション**: `maw handover --evidence-ref <ref>` で証拠参照を追加（複数指定可）
  - 例: `--evidence-ref "diff:HEAD~1" --evidence-ref "test:npm test"`
- **Takeover plan への反映**: `takeover --format plan` の出力に `id`/`summary`/`evidence_refs` を追加
- **Takeover prompt への反映**: `takeover --format prompt`（Claude 向け）に `## Summary` セクションを追加（summary 非空の場合のみ）
- **Migrate 補完**: `migrate handover --to v3 --apply` 実行時に `id`/`summary`/`evidence_refs` を自動補完
- **Validate 強化**: `validate_handover_bundle` で `id`/`summary`/`evidence_refs` の型チェックを追加

### Changed
- `lib/handover.sh`: `--summary`/`--evidence-ref` オプション追加、新規 JSON 生成に `id`/`summary`/`evidence_refs` 追加
- `lib/validate.sh`: `validate_handover_bundle` に新フィールドの型チェック追加（unknown fields は明示許容）
- `lib/takeover.sh`: `generate_takeover_plan()` に `id`/`summary`/`evidence_refs` 出力追加、`generate_claude_prompt()` に Summary セクション追加
- `lib/migrate.sh`: `migrate_handover_v2_to_v3()` で `--apply` 時に `id`/`summary`/`evidence_refs` を補完
- `tests/maw_test.bats`: v0.9.0 の検証テストを追加（11件）
- `bin/maw`: バージョン 0.9.0 に更新

### Notes
- schema `version` は 2 のまま（`id`/`summary`/`evidence_refs` は追加フィールドのみで後方互換）
- version bump は後方互換が崩れるときのみ行う方針を維持
- Phase 2（Canonical State と Evidence Refs の正式化）の入口が開いた

## [0.8.0] - 2026-02-26

### Added
- **Takeover `priority_actions` 強化**: `takeover --format plan` の `priority_actions` を「状態表示」から「次に何をするか具体的に出す」へ格上げ
  - `priority_level` フィールド（1/2/3）を全アクションに追加
  - Priority 1: `verification_status=failed` → `verify` アクション（resume_commands 付き）
  - Priority 1: `blocked_by` の `type=blocker` → owner テンプレート付き `unblock` アクション
  - Priority 2: `verification_status=pending` → `verify` アクション
  - Priority 2: `type=dependency` → 「依存先 PR/タスクの状況を確認」テンプレート
  - Priority 2: `type=issue` → 「Issue を参照して解消方法を確認」テンプレート
  - Priority 2: v2 文字列 `blocked_by` → `blocker_type: "unknown"` でフォールバック（後方互換）
  - Priority 3: カテゴリベースアクション（start/review）と `next_steps`

### Changed
- `lib/takeover.sh`: `generate_takeover_plan()` の `priority_actions` 生成ロジックを全面刷新
- `tests/maw_test.bats`: `priority_level`、blocked_by type 別テンプレート、idempotent の検証テストを追加（11件）
- `bin/maw`: バージョン 0.8.0 に更新

## [0.7.3] - 2026-02-26

### Added
- **Handover v3 object write**: `handover` コマンドで `blocked_by` を v3 オブジェクト形式で書き込み対応
  - `--blocked-by-type <type>` オプション追加（dependency|issue|blocker）
  - `--blocked-by-desc <text>` オプション追加（type と一緒に使用）
  - `--blocked-by-owner <name>` オプション追加（省略可）
  - `--blocked-by` は従来の文字列形式として後方互換維持
- **Handover bundle 完全検証**: `validate_handover_bundle()` 関数追加
  - `blocked_by` オブジェクトの `description` 必須チェック
  - `--validate` モードで呼び出し（従来の `validate_handover_json` より厳格）
- **Migrate v2→v3**: `maw migrate handover --to v3 <workspace>` コマンド追加
  - v2 文字列 `blocked_by` → v3 オブジェクト形式に変換
  - `--dry-run`（デフォルト）と `--apply` フラグ対応

### Changed
- `lib/handover.sh`: `--blocked-by-type/desc/owner` 引数追加、`validate_handover_bundle()` を使用するように変更
- `lib/validate.sh`: `validate_handover_bundle()` 関数追加
- `lib/migrate.sh`: サブコマンド形式（`maw migrate handover --to v3`）に対応、後方互換維持
- `tests/maw_test.bats`: v0.7.3 のテスト追加（13件）

## [0.7.2] - 2026-02-25

### Added
- **blocked_by v3 オブジェクトスキーマ read 対応**: `takeover` コマンドで v3 ドラフトスキーマのオブジェクト形式 `blocked_by` を読み取り対応
  - オブジェクト形式の `description` フィールドを表示
  - v2 文字列配列との後方互換性を維持
  - 混合配列（文字列+オブジェクト）に対応
  - 不正なエントリに対するフォールバック表示を実装

### Changed
- `lib/takeover.sh`: blocked_by 正規化ロジックを強化（v3 オブジェクト対応、異常系フォールバック）
- `tests/maw_test.bats`: v3 オブジェクト形式、混合配列、異常系のテストを追加

### Fixed
- description フィールドを持たない blocker オブジェクトが `[invalid blocker object]` と表示されるように修正
- 文字列/オブジェクト以外のタイプ（null/number/bool）が `[invalid blocker entry]` と表示されるように修正

## [0.6.1] - 2026-02-25

### Added
- **Handover `--blocked-by` オプション**: `maw handover` に作業ブロック要因を記録するオプションを追加
  - `--blocked-by <text>`: blocked_by 配列に追加
  - `takeover --format plan` で `blockers_count` に反映
- **Doctor `--json` exit code**: `maw doctor --json` が問題検出時に 非0 で終了するように変更
  - CI での失敗検出が可能に

### Changed
- `lib/handover.sh`: `--blocked-by` 引数と追加ロジックを実装
- `lib/doctor.sh`: JSON 出力モードで exit code を返すように変更
- `tests/maw_test.bats`: 関連テスト5件追加、version 期待値修正
- `docs/ja/commands.md`, `docs/en/commands.md`: `--blocked-by` と `doctor --json` exit code のドキュメント追加

## [0.6.0] - 2026-02-24

### Added
- **Handover 編集フラグ**: `maw handover` に JSON を直接編集するオプションを追加
  - `--next-step <text>`: next_steps 配列に追加
  - `--decision <text>`: decisions 配列に追加（タイムスタンプ付き）
  - `--risk <text>`: risks 配列に追加
  - `--risk-severity <level>`: リスク重要度 (low|medium|high|critical)
  - `--resume-command <cmd>`: resume_commands 配列に追加
  - `--verification-status <s>`: verification_status を更新 (pending|passed|failed|skipped)
- **Takeover Plan 優先順位ロジック強化**: スコアリングシステム導入
  - 総合スコア (0-100) を計算
  - カテゴリ判定: ready (80-100), caution (50-79), blocked (0-49)
  - 各要素の重み付け: verification_status (40%), state (20%), blockers (20%), risks (20%)
- **Doctor JSON v2**: スキーマ拡張
  - `format`: "doctor" フィールド追加
  - `maw_version`: maw バージョン情報追加
  - `health_score`: 全体ヘルススコア (0-100) 追加
  - `categories`: カテゴリ別ステータスとスコア追加 (worktree, symlink, lockfile, git, claims, stale_claims)
  - 各チェックに category フィールド追加
- **Smoke Test CI**: 基本的な機能をテストする GitHub Actions workflow 追加

### Changed
- `lib/handover.sh`: 引数パースと編集モード実装
- `lib/takeover.sh`: generate_takeover_plan をスコアリングベースに変更
- `lib/doctor.sh`: cmd_doctor_json_output を v2 スキーマに変更

## [0.5.1] - 2026-02-24

### Fixed
- **セキュリティ修正**: Python コードインジェクションの脆弱性（HIGH）
  - 相対パス計算を環境変数経由で安全に実行する `calculate_relative_path()` 関数を追加
  - `lib/spawn.sh`, `lib/doctor.sh` で脆弱な Python コマンドを置換
- **セキュリティ修正**: パストラバーサル保護の欠如（MEDIUM）
  - `normalize_claim_path()` に `../` チェックと realpath 境界検証を追加
  - `validate_claim_path()` 関数で claim パスのバリデーションを強化
- **セキュリティ修正**: 入力バリデーションの不足（MEDIUM）
  - `validate_workspace_name()` 関数でワークスペース名のバリデーションを追加
  - 予約語、文字種、長さのチェックを実装

### Added
- `lib/validate.sh`: 入力バリデーションライブラリ
  - `validate_workspace_name()`: ワークスペース名バリデーション
  - `validate_claim_path()`: claim パスバリデーション
  - `calculate_relative_path()`: 安全な相対パス計算
- `tests/security_test.bats`: セキュリティテスト（30 ケース追加）
- `docs/ja/security.md`: セキュリティドキュメント

### Changed
- `lib/spawn.sh`: ワークスペース名バリデーションを追加、安全な相対パス計算を使用
- `lib/doctor.sh`: 安全な相対パス計算を使用
- `lib/claim.sh`, `lib/unclaim.sh`: `validate_claim_path()` を使用
- README.md: セキュリティドキュメントへのリンクを追加

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
