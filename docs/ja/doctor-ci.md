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

## 公開契約

`maw doctor --json` は公開 JSON 契約です。key 順は固定しませんが、以下の top-level key は必須です。

| key | type | 説明 |
|-----|------|------|
| `version` | integer | 現在は `2` |
| `format` | string | 現在は `"doctor"` |
| `timestamp` | string | UTC timestamp |
| `maw_version` | string | `maw` バージョン |
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

現在の score 規約:
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

## Default simple mode

`--exit-code-mode` を省略した場合は `simple` が使われます。
- `failed = 0` かつ warning のみなら `0`
- `failed > 0` なら `1`

CI で `if: always()` などと組み合わせて結果をキャプチャ可能:

```yaml
      - name: Always run doctor
        if: always()
        run: maw doctor --json > health.json
```

## Exit Code Contract

`--exit-code-mode` で exit code 契約を制御できます。

### Exit Code Table

| Mode   | No issues | Warning only | Failed issues | Invalid mode |
|--------|-----------|--------------|---------------|--------------|
| simple | 0         | 0            | 1             | 1            |
| multi  | 0         | 2            | 1             | 1            |

### Mode 説明

- **simple** (デフォルト): 問題があれば失敗 (exit 1)
  - 警告のみの場合は成功 (exit 0)
  - CI で「問題があれば失敗させたい」場合に適している

- **multi**: 警告と失敗を区別
  - 警告のみ: exit 2
  - 失敗あり: exit 1
  - CI で「警告は通知したいが失敗はさせたくない」場合に適している

### CI Examples

#### Simple mode (default) - fail on any issues

```yaml
- name: Health check (fail on issues)
  run: |
    maw doctor --json --exit-code-mode simple > health.json
    # failed > 0 で exit 1 になるため、CI が失敗する
```

#### Multi mode - fail only on critical, notify on warnings

```yaml
- name: Health check (multi mode)
  run: |
    maw doctor --json --exit-code-mode multi > health.json
    # failed > 0 で exit 1、warnings only で exit 2

# 警告のみで CI を続ける場合
- name: Health check (warnings allowed)
  run: |
    maw doctor --json --exit-code-mode multi || true
    # exit 2 (warning only) を無視して続行
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
