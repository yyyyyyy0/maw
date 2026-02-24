# セキュリティ

maw は複数の AI エージェントが同一リポジトリで並列作業するためのツールであり、セキュリティを重要視しています。

## 入力バリデーション

### ワークスペース名

ワークスペース名は以下のルールに従う必要があります：

- **長さ**: 1-63文字
- **使用可能文字**: 英数字とアンダースコアのみ (`[a-zA-Z0-9_]+`)
- **先頭文字**: 英字のみ
- **予約語禁止**: `init`, `spawn`, `claim`, `unclaim` などの maw コマンド名

```bash
# 有効なワークスペース名
maw spawn my_workspace_123
maw spawn feature_auth

# 無効なワークスペース名（エラー）
maw spawn 123workspace    # 数字始まり
maw spawn my-workspace    # ハイフン使用
maw spawn _private        # アンダースコア始まり
maw spawn init            # 予約語
```

### claim パス

ファイルやディレクトリの排他宣言（claim）を行うパスには以下の制限があります：

- **相対パスのみ**: 絶対パス（`/` で始まるパス）は使用できません
- **パストラバーサル禁止**: `../` を含むパスは拒否されます
- **nullバイト禁止**: nullバイトを含むパスは拒否されます
- **制御文字禁止**: 制御文字（タブと改行を除く）を含むパスは拒否されます

```bash
# 有効な claim パス
maw claim src/auth.ts
maw claim src/components/
maw claim ./lib/utils.ts

# 無効な claim パス（エラー）
maw claim /etc/passwd           # 絶対パス
maw claim ../../etc/passwd      # パストラバーサル
maw claim ../secret/key.pem     # パストラバーサル
```

## セキュリティ対策の実装

### 1. Python コードインジェクション対策

以前のバージョンでは、相対パス計算に Python を使用していましたが、引数のエスケープが不十分でコードインジェクションの脆弱性がありました。

現在は環境変数経由で安全にパスを渡すよう修正されています：

```bash
# 以前（脆弱）
rel_path="$(python3 -c "import os.path; print(os.path.relpath('${source_dir}', '${ws_path}'))")"

# 現在（安全）
rel_path="$(calculate_relative_path "$source_dir" "$ws_path")"
```

### 2. パストラバーサル保護

`normalize_claim_path()` 関数と `validate_claim_path()` 関数で以下のチェックを行います：

1. `../` シーケンスの検出と拒否
2. 絶対パスの正規化とルート境界の検証
3. `realpath` による解決後のパスがプロジェクトルート内にあることを確認

### 3. 並行アクセス保護

claim システムはファイルとディレクトリの排他的な変更を保護します：

- 完全一致: 同じパスの claim は競合
- ディレクトリ包含: `src/` の claim は `src/auth.ts` の claim と競合
- 逆包含: `src/auth.ts` の claim は `src/` の claim と競合

## レポート

セキュリティ上の問題を発見した場合は、GitHub Issues にて報告をお願いします。

## ベストプラクティス

1. **入力を検証する**: ユーザー入力や外部入力は必ず検証してください
2. **相対パスを使用する**: claim には常にプロジェクトルートからの相対パスを使用してください
3. **ワークスペース名をシンプルに保つ**: 記号や特殊文字を避け、英数字とアンダースコアのみを使用してください
4. **定期的に doctor を実行する**: `maw doctor --fix` で整合性をチェックしてください
