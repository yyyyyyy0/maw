name: maw-workspace

description: |
  maw (Multi-Agent Workspace) を使用して、並列エージェント作業のワークスペース管理・
  ファイル排他宣言・引き継ぎドキュメント生成・ブランチマージを行うスキル。

  R-COLLAB-001「並列作業では共有ファイル編集前に競合リスクを確認する」の具体的な実装手段として機能する。
  ファイル編集前に `maw claim` を実行することで競合を事前防止し、作業完了後に
  `maw handover` → `maw merge` で安全に統合する。

allowed-tools:
  - Bash（maw コマンド実行のみ）
  - Read（.maw/handovers/*.md の読み込み）

inputs:
  | 入力             | 型       | 必須   | 説明                                        |
  |-----------------|---------|-------|---------------------------------------------|
  | workspace_name  | string  | MUST  | ワークスペース名（英数字・ハイフン）           |
  | target_files    | string[]| SHOULD| 作業対象ファイル/ディレクトリのパス一覧        |
  | issue_number    | string  | MAY   | 紐付ける Issue 番号                           |
  | agent_name      | string  | MAY   | エージェント種別（例: claude, codex）          |
  | base_branch     | string  | MAY   | spawn の分岐元（デフォルト: origin/main）/ merge のマージ先（デフォルト: main） |
  | ttl_minutes     | integer | MAY   | Claim の有効期限（分）。省略時は無期限         |

outputs:
  | 出力             | 型       | 説明                                         |
  |-----------------|---------|----------------------------------------------|
  | workspace_path  | string  | 作成された worktree の絶対パス                |
  | branch_name     | string  | ワークスペースのブランチ名                     |
  | handover_path   | string  | 生成された handover ドキュメントのパス         |
  | claimed_paths   | string[]| claim したファイル/ディレクトリの一覧          |

constraints:
  - "[MUST] ファイル編集前に必ず maw claim を実行する（R-COLLAB-001 / R-MAW-CLAIM-001 準拠）。claim なしでの編集はこのスキルの制約違反である。"
  - "[MUST] 他 WS が claim 済みのファイルは編集を中止してユーザーに報告する。報告内容: claim 中の WS 名・エージェント名・有効期限。"
  - "[MUST] 作業完了時は maw handover → maw merge の順で終了する。handover を省略すると次のエージェントがコンテキストを失う。"
  - "[MUST] maw status を作業開始時・終了時に必ず確認する。他エージェントの状況を把握せずに作業を開始してはならない。"
  - "[MUST] maw doctor でエラーが報告された場合は --fix を実行してから作業を開始する。"
  - "[MUST] maw spawn で --from を省略した場合は origin/main を fetch して分岐する。origin/main の fetch/resolve に失敗した場合は中断し、他ブランチへの無断フォールバックは禁止する。"
  - "[SHOULD] 長時間作業の Claim には適切な TTL を設定する（例: --ttl 120）。"

steps:
  1. "[作業開始前] maw status で現状確認 — 既存 WS の一覧と claim 状況を把握し、競合の可能性があるファイルを特定する。"
  2. "[WS 作成] maw spawn <workspace_name> [--agent <agent_name>] [--issue <issue_number>] [--from <base_branch>] — --from 指定時はその分岐元を優先。未指定時は origin/main を fetch して最新を分岐元に使う。origin/main を fetch/resolve できない場合は失敗（フォールバックなし）。すでに WS が存在する場合はスキップ。"
  3. "[ファイル排他] maw claim <target_file_or_dir> [--ttl <minutes>] — 編集する各ファイルまたはディレクトリを claim する。競合（他 WS が claim 済み）の場合は編集を中止してユーザーに報告する。"
  4. "[実装] 通常の作業（編集・コミット・テスト）を行う。worktree は .maw-workspaces/<name>/ にある。追加ファイルが必要になった場合は Step 3 に戻る。"
  5. "[引き継ぎ] maw handover [--workspace <name>] — .maw/handovers/ws-<name>.md を生成する。生成後、Notes セクションに必要な追記を行う。"
  6. "[マージ] maw merge <workspace_name> [--base <branch>] — target branch へ統合する。--dry-run で事前確認を推奨する。マージ後は claims が自動削除され、WS が cleanup される。"
  7. "[完了確認] maw status で後処理を確認する — 残存する WS・claim がないことを確認し、必要なら maw doctor --fix で整合性を修復する。"

# 参照
# - docs/ja/commands.md — コマンドリファレンス（日本語）
# - docs/ja/concepts.md — 設計思想（日本語）
# - docs/en/commands.md — Command Reference
# - docs/en/concepts.md — Concepts
# - AGENTS.md §9: R-COLLAB-001
# - AGENTS.extensions.md §13: R-MAW-*
