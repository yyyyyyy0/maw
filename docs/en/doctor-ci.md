# CI Integration

`maw doctor --json` can be used as a machine-readable health gate in CI pipelines.

## JSON Output

```bash
maw doctor --json
```

Example output:

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

## Public Contract

`maw doctor --json` is a public JSON contract. Key order is not fixed, but the following top-level keys are required.

| Key | Type | Notes |
|-----|------|-------|
| `version` | integer | Currently `2` |
| `format` | string | Currently `"doctor"` |
| `timestamp` | string | UTC timestamp |
| `maw_version` | string | Current `maw` version |
| `health_score` | integer | `0..100` |
| `summary` | object | Must contain the required subkeys below |
| `categories` | object | Must contain the 6 required category keys below |
| `checks` | array<object> | Each entry must satisfy the minimum contract below |

### `summary` Required Subkeys

| Key | Type |
|-----|------|
| `total_checks` | integer >= 0 |
| `passed` | integer >= 0 |
| `failed` | integer >= 0 |
| `warnings` | integer >= 0 |
| `fixable` | integer >= 0 |

### `categories` Required Keys

Required categories are `worktree`, `symlink`, `lockfile`, `git`, `claims`, and `stale_claims`. Each category object requires:

| Key | Type | Notes |
|-----|------|-------|
| `status` | `passed \| warning \| failed` | Category status |
| `score` | integer | `0..100` |

Current score rules:
- `passed = 100`
- `failed = 0`
- `warning = 70` for `symlink`, `lockfile`, and `git`
- `warning = 80` for `stale_claims`

### `checks[*]` Minimum Contract

Each check object requires:

| Key | Type |
|-----|------|
| `name` | string |
| `status` | `passed \| warning \| failed` |
| `severity` | `none \| warning \| error` |
| `message` | string |
| `fixable` | boolean |
| `category` | `worktree \| symlink \| lockfile \| git \| claims \| stale_claims` |

## GitHub Actions Examples

### Basic health check

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

          failed=$(echo "$health" | jq -r '.summary.failed')
          if [[ "$failed" -gt 0 ]]; then
            echo "::error::Workspace health check failed"
            exit 1
          fi
```

### Report failed checks

```yaml
      - name: Doctor with detailed output
        run: |
          health=$(maw doctor --json)
          failed_checks=$(echo "$health" | jq -r '.checks[] | select(.status == "failed") | "- \(.name): \(.message)"')

          if [[ -n "$failed_checks" ]]; then
            echo "::error::Failed checks:"
            echo "$failed_checks"
            exit 1
          fi
```

## jq Examples

### Read summary

```bash
maw doctor --json | jq '.summary'
```

### Read categories

```bash
maw doctor --json | jq '.categories'
```

### Read failed checks only

```bash
maw doctor --json | jq '.checks[] | select(.status == "failed")'
```

## Default simple mode

If `--exit-code-mode` is omitted, `simple` is used.
- warning only => `0`
- any failed issue => `1`

```yaml
- name: Always run doctor
  if: always()
  run: maw doctor --json > health.json
```

## Exit Code Contract

`--exit-code-mode` controls the exit code policy.

| Mode | No issues | Warning only | Failed issues | Invalid mode |
|------|-----------|--------------|---------------|--------------|
| `simple` | 0 | 0 | 1 | 1 |
| `multi` | 0 | 2 | 1 | 1 |

### Mode Notes

- **simple** (default): fail only when `failed > 0`
- **multi**: distinguish warning-only (`2`) from failed (`1`)

### CI Examples

```yaml
- name: Health check (simple)
  run: maw doctor --json --exit-code-mode simple > health.json

- name: Health check (multi)
  run: maw doctor --json --exit-code-mode multi > health.json

- name: Health check (warnings allowed)
  run: maw doctor --json --exit-code-mode multi || true
```
