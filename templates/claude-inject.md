
## Multi-Agent Workspace (maw)

このワークスペースは `maw` によって管理されています。

### ルール

- **ファイル排他**: 作業前に `maw claim <file>` でファイルを宣言してください
- **状態共有**: 作業完了時に `maw handover` で引き継ぎドキュメントを生成してください
- **依存パッケージ**: `node_modules/` は symlink です。`npm install` / `yarn add` はメインプロジェクトで実行してください
- **ブランチ**: このワークスペース専用のブランチで作業しています

### コマンド

```bash
maw status          # 全ワークスペースの状況確認
maw claim <file>    # ファイル排他宣言
maw unclaim <file>  # 排他解除
maw handover        # 引き継ぎドキュメント生成
```
