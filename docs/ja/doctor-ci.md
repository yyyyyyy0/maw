# CI Integration

`maw doctor --json` を使用して、CI パイプラインでワークスペースの健全性チェックを自動化できます。

## JSON 出力形式

```bash
maw doctor --json
```

出力例:

```json
{
  "version": 2,
  "format": "doctor",
  "timestamp": "2025-02-25T12:34:56Z",
  "maw_version": "0.6.1",
  "health_score": 85,
  "summary": {
    "total_checks": 6,
    "passed": 5,
    "failed": 1,
    "warnings": 0,
    "fixable": 1
  },
  "categories": {
    "worktree": {"status": "passed", "score": 100},
    "symlink": {"status": "passed", "score": 100},
    "lockfile": {"status": "passed", "score": 100},
    "git": {"status": "passed", "score": 100},
    "claims": {"status": "failed", "score": 0},
    "stale_claims": {"status": "passed", "score": 100}
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

## GitHub Actions での使用例

### 基本的なヘルスチェック

```yaml
name: Workspace Health Check

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

jobs:
  doctor:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install maw
        run: |
          git clone https://github.com/yyyyyyy0/maw.git ~/.maw-cli
          ~/.maw-cli/install.sh

      - name: Install dependencies
        run: sudo apt-get install -y jq

      - name: Check workspace health
        run: |
          health=$(maw doctor --json)
          echo "$health"

          # サマリーをチェック
          failed=$(echo "$health" | jq -r '.summary.failed')
          if [[ "$failed" -gt 0 ]]; then
            echo "::error::Workspace health check failed"
            exit 1
          fi

          echo "✅ Workspace health check passed"
```

### カテゴリ別チェック

```yaml
      - name: Check specific categories
        run: |
          health=$(maw doctor --json)

          # worktree ステータス
          worktree_status=$(echo "$health" | jq -r '.categories.worktree.status')
          if [[ "$worktree_status" == "failed" ]]; then
            echo "::error::Worktree issues detected"
            exit 1
          fi

          # claims ステータス
          claims_status=$(echo "$health" | jq -r '.categories.claims.status')
          if [[ "$claims_status" == "failed" ]]; then
            echo "::warning::Claims issues detected"
          fi

          # ヘルススコアで判定
          score=$(echo "$health" | jq -r '.health_score')
          if [[ "$score" -lt 70 ]]; then
            echo "::error::Health score too low: $score"
            exit 1
          fi
```

### 失敗時に詳細を表示

```yaml
      - name: Doctor with detailed output
        run: |
          # JSON と通常出力を両方取得
          health=$(maw doctor --json)

          # 失敗したチェックを抽出
          failed_checks=$(echo "$health" | jq -r '.checks[] | select(.status == "failed") | "- \(.name): \(.message)"')

          if [[ -n "$failed_checks" ]]; then
            echo "::error::Failed checks:"
            echo "$failed_checks"
            exit 1
          fi
```

### PR コメントに結果を投稿

```yaml
      - name: Report health status
        if: always()
        run: |
          health=$(maw doctor --json)
          score=$(echo "$health" | jq -r '.health_score')
          failed=$(echo "$health" | jq -r '.summary.failed')
          warnings=$(echo "$health" | jq -r '.summary.warnings')

          comment="## Workspace Health Report\n\n"
          comment+="- **Health Score**: $score/100\n"
          comment+="- **Failed**: $failed\n"
          comment+="- **Warnings**: $warnings\n"

          # jq でカテゴリ別ステータスを整形
          categories=$(echo "$health" | jq -r '.categories | to_entries[] | "- **\(.key)**: \(.value.status) (\(.value.score)/100)"')
          comment+="\n### Categories\n\n$categories"

          echo "$comment" > $GITHUB_STEP_SUMMARY
```

## jq での活用例

### サマリー取得

```bash
maw doctor --json | jq '.summary'
# {"total_checks": 6, "passed": 5, "failed": 1, "warnings": 0, "fixable": 1}
```

### カテゴリ別ステータス

```bash
maw doctor --json | jq '.categories'
# {"worktree": {"status": "passed", "score": 100}, ...}
```

### 失敗したチェックのみ抽出

```bash
maw doctor --json | jq '.checks[] | select(.status == "failed")'
```

### ヘルススコアで条件分岐

```bash
score=$(maw doctor --json | jq '.health_score')
if [[ "$score" -lt 70 ]]; then
  echo "Health score too low: $score"
  exit 1
fi
```

### fixable な問題があるかチェック

```bash
fixable=$(maw doctor --json | jq '.summary.fixable')
if [[ "$fixable" -gt 0 ]]; then
  echo "There are $fixable fixable issues"
  maw doctor --fix
fi
```

## Exit Behavior

| 状態 | Exit Code |
|------|-----------|
| 問題なし | 0 |
| 問題検出時 (`failed > 0`) | 1 |

CI で `if: always()` などと組み合わせて結果をキャプチャ可能:

```yaml
      - name: Always run doctor
        if: always()
        run: maw doctor --json > health.json
```

## テスト・ステージへの統合

```yaml
test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    # ... 他のテスト ...

    - name: Pre-merge health check
      run: |
        health=$(maw doctor --json)
        failed=$(echo "$health" | jq -r '.summary.failed')
        if [[ "$failed" -gt 0 ]]; then
          echo "::error::Cannot merge with failed health checks"
          exit 1
        fi
```
