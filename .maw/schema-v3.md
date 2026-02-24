# Handover Schema v3 草案

## 概要

v3 schema は `blocked_by` フィールドを拡張し、より詳細なブロッカー情報を記録できるようにします。

## v2 からの変更点

| 項目 | v2 | v3 |
|------|----|----|
| `version` | 2 | 3 |
| `blocked_by` | 文字列配列 | 文字列またはオブジェクト配列（後方互換） |

## blocked_by フィールド仕様

### v2 形式（後方互換）

```json
{
  "version": 2,
  "blocked_by": [
    "Waiting for lib-v2 release",
    "Need design approval",
    "API rate limit"
  ]
}
```

### v3 形式（推奨）

```json
{
  "version": 3,
  "blocked_by": [
    {
      "type": "dependency",
      "description": "Waiting for lib-v2 release",
      "resolved": false
    },
    {
      "type": "issue",
      "description": "Need design approval",
      "resolved": false
    },
    {
      "type": "blocker",
      "description": "API rate limit exceeded",
      "resolved": true,
      "resolved_at": "2025-02-25T12:00:00Z"
    }
  ]
}
```

### 混合形式（v3 で有効）

```json
{
  "version": 3,
  "blocked_by": [
    "Simple string blocker (v2 style)",
    {
      "type": "dependency",
      "description": "Detailed blocker (v3 style)",
      "resolved": false
    }
  ]
}
```

## type フィールドの値

| 値 | 説明 |
|----|------|
| `dependency` | 外部依存（ライブラリ、API、サービス等） |
| `issue` | 課題・懸念事項（設計、技術的負債等） |
| `blocker` | 実行上の障害（バグ、リソース制限等） |

## resolved フィールド

| 値 | 説明 |
|----|------|
| `false` | 未解決（デフォルト） |
| `true` | 解決済み（`resolved_at` と共に使用） |

## 移行方針

### v2 → v3 自動移行

v2 形式の handover JSON を読み込む際、自動的に v3 に変換します:

1. `version` が 2 の場合、v3 の形式に従って処理
2. 文字列配列形式の `blocked_by` はそのまま保持
3. 新規追加時はオブジェクト形式を推奨

### validate.sh の更新

```bash
# v3 では文字列とオブジェクトの両方を許容
validate_blocked_by_v3() {
  local json_file="$1"
  local blocked_by

  blocked_by="$(jq -c '.blocked_by[]' "$json_file")"

  while IFS= read -r item; do
    # 文字列形式（v2 互換）
    if [[ "$item" =~ ^\".*\"$ ]]; then
      continue
    fi

    # オブジェクト形式（v3）
    local type
    type="$(echo "$item" | jq -r '.type // empty')"
    if [[ -n "$type" ]]; then
      validate_handover_field "blocker type" "$type" "dependency issue blocker" || return 1
    fi
  done <<< "$blocked_by"
}
```

## 実装計画

### Phase P3-1（完了）
- [x] v3 schema 仕様書の作成
- [x] 移行方針の策定

### Phase P3-2（将来）
- [ ] validate.sh の更新（文字列とオブジェクトの両方を許容）
- [ ] takeover.sh でのオブジェクト形式の表示対応
- [ ] handover.sh の `--blocked-by` オプションでオブジェクト形式をサポート

## 付録: 完全な v3 JSON 例

```json
{
  "version": 3,
  "workspace": "feature-auth",
  "branch": "feature/auth",
  "base_branch": "main",
  "agent": "claude",
  "issue": "42",
  "diff_stat": " src/auth.ts | 12 ++++++++++++\n 1 file changed, 12 insertions(+)",
  "diff": "diff --git a/src/auth.ts b/src/auth.ts\n...",
  "log": [
    "feat: add authentication",
    "fix: resolve token refresh issue"
  ],
  "claims": {
    "src/auth.ts": {
      "workspace": "feature-auth",
      "agent": "claude",
      "claimed_at": "2025-02-25T12:00:00Z",
      "expires_at": "2025-02-25T14:00:00Z"
    }
  },
  "state": "clean",
  "next_steps": [
    "Write unit tests",
    "Update documentation"
  ],
  "decisions": [
    {
      "description": "Use JWT for authentication",
      "timestamp": "2025-02-25T12:00:00Z"
    }
  ],
  "risks": [
    {
      "description": "Token storage security concern",
      "severity": "medium",
      "timestamp": "2025-02-25T12:00:00Z"
    }
  ],
  "blocked_by": [
    {
      "type": "dependency",
      "description": "Waiting for lib-v2 release",
      "resolved": false
    },
    {
      "type": "issue",
      "description": "Need design approval",
      "resolved": false
    }
  ],
  "resume_commands": [
    "cd .maw/workspaces/feature-auth",
    "npm test"
  ],
  "verification_status": "pending",
  "generated_at": "2025-02-25T12:34:56Z"
}
```
