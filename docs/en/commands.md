# Command Reference

## Global Options

```
maw [--version] [--help]
```

| Option | Description |
|--------|-------------|
| `--version` | Print version and exit |
| `--help` | Print help and exit |

---

## `maw init`

Initialize a project for maw.

### Synopsis

```bash
maw init
```

### Behavior

1. Verify the directory is inside a git repository
2. Create `.maw/`, `.maw-workspaces/`, and `.maw/handovers/`
3. Auto-detect ecosystem (nodejs / python / rust / go / generic)
4. Auto-detect package manager for nodejs (yarn / npm / pnpm / bun)
5. Append `.maw/` and `.maw-workspaces/` to `.gitignore`
6. Generate `config.json`, `state.json`, and `claims.json`
7. Save lockfile SHA-256 to `.maw/lockfile-hash`

### Files Created

- `.maw/config.json` — Project configuration
- `.maw/state.json` — Workspace state (initially empty)
- `.maw/claims.json` — File claims (initially empty)
- `.maw/lockfile-hash` — Lockfile hash

### Notes

- Fails if `.maw/` already exists
- Requires a git repository

---

## `maw spawn <name> [options]`

Create a new workspace.

### Synopsis

```bash
maw spawn <name> [--branch <name>] [--issue <number>] [--agent <name>]
                  [--isolated] [--from <branch>]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<name>` | Workspace name (alphanumeric and hyphens recommended) |

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--branch <name>` | Specify branch name directly | `<name>` |
| `--issue <number>` | Issue number (branch: `issue/<number>-<name>`) | — |
| `--agent <name>` | Agent type (branch: `<agent>/<name>`) | — |
| `--isolated` | Install dependencies independently instead of symlinking | false |
| `--from <branch>` | Base branch to create worktree from (highest priority when set) | `origin/main` (fetched when `--from` is omitted) |

### Examples

```bash
maw spawn feature-auth
maw spawn feature-auth --agent claude
maw spawn feature-auth --issue 42
maw spawn feature-auth --agent claude --issue 42  # branch: claude/feature-auth
maw spawn feature-auth --isolated                 # independent node_modules
maw spawn feature-auth --from develop             # prefer develop over origin/main
```

### Behavior

1. If `--from <branch>` is provided, use it as the base branch with top priority
2. If `--from` is omitted, fetch `origin/main` and use the latest fetched commit as the base branch
3. If `origin/main` cannot be fetched or resolved, fail (no fallback)
4. Create a git worktree on the target branch and check out to `.maw-workspaces/<name>/`
5. Create symlinks per ecosystem config (skipped with `--isolated`) and register workspace info in `state.json`

---

## `maw list`

Display all workspaces in a table.

### Synopsis

```bash
maw list
```

### Example Output

```
NAME             BRANCH                         AGENT      ISSUE    CREATED
------------------------------------------------------------------------------------------
feature-auth     claude/feature-auth            claude     42       2026-02-20
bugfix-login     issue/99-bugfix-login          -          99       2026-02-20
```

---

## `maw status`

Display workspace status and file claim information.

### Synopsis

```bash
maw status
```

### Example Output

```
=== Workspaces ===
     NAME             BRANCH                         AGENT      ISSUE    CREATED
  ------------------------------------------------------------------------------------------------
  -> feature-auth     claude/feature-auth            claude     42       2026-02-20
     bugfix-login     issue/99-bugfix-login          -          99       2026-02-20

=== Claims ===
  FILE                           WORKSPACE        AGENT      CLAIMED              EXPIRES
  -----------------------------------------------------------------------------------------
  src/auth.ts                    feature-auth     claude     2026-02-20 10:00     2026-02-20 11:30
```

### Display Details

- `->` marks the workspace corresponding to the current working directory
- EXPIRES column:
  - No expiry: `-`
  - Expiry set, more than 10 minutes remaining: displayed in yellow
  - Expired: displayed in red

---

## `maw claim <path> [options]`

Declare an exclusive claim on a file or directory.

### Synopsis

```bash
maw claim <path> [--workspace <name>] [--ttl <minutes>]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<path>` | File or directory path to claim |

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--workspace <name>` | Explicitly specify workspace name | auto-detect from current dir |
| `--ttl <minutes>` | Expiry time in minutes. Omit for no expiry | none |

### Examples

```bash
maw claim src/auth.ts
maw claim src/components/ --workspace ws1
maw claim src/auth.ts --ttl 90      # expires in 90 minutes
```

### Conflict Rules

| Situation | Result |
|-----------|--------|
| Another WS already claims the same file | Error |
| Another WS claims the parent directory | Error |
| Another WS claims a child file (when claiming directory) | Error |
| Same WS re-claims the same path | Idempotent (update) |
| Claiming over an expired claim | Success |

---

## `maw unclaim <path> [options]`

Release a file claim.

### Synopsis

```bash
maw unclaim <path> [--workspace <name>] [--force]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<path>` | File or directory path to unclaim |

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--workspace <name>` | Explicitly specify workspace name | auto-detect from current dir |
| `--force` | Force-release even claims owned by other workspaces | false |

### Examples

```bash
maw unclaim src/auth.ts               # release own claim
maw unclaim src/auth.ts --force       # force-release any claim
```

---

## `maw handover [options]`

Generate or edit a handover document. In addition to Markdown, a JSON sidecar is also produced (v0.5.0+).

### Synopsis

```bash
maw handover [--workspace <name>] [--scope full|summary|evidence] [--validate <name>] [edit options]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--workspace <name>` | Explicitly specify workspace name | auto-detect from current dir |
| `--scope <mode>` | Output scope | `full` |
| `--validate <name>` | Validate handover JSON integrity (no generation) | — |

### Edit Options (v0.6.0+)

| Option | Description |
|--------|-------------|
| `--next-step <text>` | Add to next_steps array |
| `--decision <text>` | Add to decisions array (with timestamp) |
| `--risk <text>` | Add to risks array |
| `--risk-severity <level>` | Risk severity (low\|medium\|high\|critical, default: medium) |
| `--resume-command <cmd>` | Add to resume_commands array |
| `--verification-status <s>` | Update verification_status (pending\|passed\|failed\|skipped) |
| `--blocked-by <text>` | Add a legacy string entry to `blocked_by` (backward-compat mode) |
| `--blocked-by-type <type>` | Add a typed blocker entry (`dependency\|issue\|blocker`) |
| `--blocked-by-desc <text>` | Description for the typed blocker entry (used with `--blocked-by-type`) |
| `--blocked-by-owner <name>` | Optional owner for the typed blocker entry |
| `--unblock <text>` | Remove `blocked_by` entries by case-insensitive partial match |
| `--clear-blockers` | Clear all `blocked_by` entries |

### --scope Modes

| Mode | Markdown | JSON sidecar | Description |
|------|---------|-------------|-------------|
| `full` | Yes | Yes | All sections (default) |
| `summary` | Yes | Yes | Branch, diff stat, and next_steps only (no full diff) |
| `evidence` | Yes | **No** | git log, changed files, and uncommitted changes only |

### Output

```
.maw/handovers/ws-<name>.md    # Markdown (human-readable)
.maw/handovers/ws-<name>.json  # JSON (for LLMs / maw takeover) — except scope=evidence
```

### JSON Sidecar Schema (v2)

```json
{
  "version": 2,
  "workspace": "feature-auth",
  "branch": "claude/feature-auth",
  "base_branch": "main",
  "agent": "claude",
  "issue": "42",
  "summary": "Add JWT authentication",
  "decisions": [
    {
      "topic": "Auth library",
      "decision": "Use jsonwebtoken",
      "rationale": "Most widely used in Node.js ecosystem"
    }
  ],
  "risks": [
    {
      "description": "Token expiration configuration",
      "mitigation": "Make configurable via environment variables"
    }
  ],
  "blocked_by": [
    {
      "type": "dependency",
      "description": "External API specification",
      "resolved": false,
      "owner": "platform-team"
    }
  ],
  "verification_status": "pending",
  "diff_stat": "...",
  "diff": "... (4096 byte limit)",
  "log": ["abc1234 fix: auth bug"],
  "claims": { "src/auth.ts": { "workspace": "...", "agent": "...", "claimed_at": "...", "expires_at": null } },
  "state": "clean",
  "next_steps": [],
  "resume_commands": ["npm test", "npm run build"],
  "generated_at": "2026-02-24T10:00:00Z"
}
```

**state values**: `clean` (no changes) / `dirty` (uncommitted changes) / `stash` (stash entries present)

### `blocked_by` Contract

`blocked_by` accepts either of the following entry types:

- Legacy string entry: `"waiting for external review"`
- Typed object entry: `{ "type": "...", "description": "...", "resolved": false, "owner": "..." }`

Typed object entries are the public contract for new writes:

| Key | Type | Notes |
|-----|------|-------|
| `type` | `dependency \| issue \| blocker` | Required |
| `description` | string | Required, non-empty |
| `resolved` | boolean | Required |
| `owner` | string | Optional |

Compatibility rules:
- `--blocked-by` remains available for backward compatibility, but new writes should prefer `--blocked-by-type` + `--blocked-by-desc`
- `maw handover --validate` enforces the typed object contract for object entries
- Normal handover generation still writes `version: 2`
- `maw migrate handover --to v3` is the normalization path for converting legacy string blockers into typed object blockers and backfilling missing `resolved: false` on legacy object blockers, including pre-existing `version: 3` bundles

### Content Generated (Markdown)

- Workspace info (branch, agent, issue)
- Commit history (`git log --oneline`)
- Changed files (`git diff --name-status`)
- Uncommitted changes (`git status --short`)
- Claims list (for this workspace only)
- Notes (free-form placeholder)

---

## `maw takeover [<name>] [options]`

Read a handover JSON bundle and print a session-resume prompt (v0.5.0+).

### Synopsis

```bash
maw takeover [<name>] [--format md|json|prompt|plan]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<name>` | Workspace name (auto-detected if omitted) |

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--format <mode>` | Output format | `prompt` |

### --format Modes

| Mode | Description |
|------|-------------|
| `prompt` | Structured session-resume prompt for agents |
| `plan` | Public readiness-contract JSON for downstream automation / CI — v0.6.0+ |
| `json` | Raw JSON sidecar output (pretty-printed via `jq .`) |
| `md` | Raw Markdown handover file output |

### --format plan Public Contract (v0.6.0+)

`plan` is a public JSON contract. Key order is not fixed, but the following top-level keys are required.

| Key | Type | Notes |
|-----|------|-------|
| `id` | string | Uses `""` when missing from the handover bundle |
| `summary` | string | Uses `""` when missing from the handover bundle |
| `evidence_refs` | array<string> | Uses `[]` when missing from the handover bundle |
| `workspace` | string | Workspace name |
| `branch` | string | Target branch name |
| `verification_status` | string | Supported values: `pending \| passed \| failed \| skipped`. Unsupported values are still returned, but scoring treats them as `unknown` = 30 |
| `state` | string | Supported values: `clean \| dirty \| stash`. Unsupported values are still returned, but scoring treats them as `unknown` = 50 |
| `decisions_count` | integer >= 0 | Number of decisions |
| `risks_count` | integer >= 0 | Number of risks |
| `blockers_count` | integer >= 0 | Total number of `blocked_by` entries |
| `blockers` | array<string> | `blocked_by` normalized to descriptions, capped at 3 items |
| `score` | integer | `0..100` |
| `category` | string | `ready \| caution \| blocked` |
| `priority_actions` | array<object> | Each entry must satisfy the minimum contract below |
| `resume_commands` | array<string> | Candidate commands to resume work |

### `priority_actions[*]` Minimum Contract

Each action object requires the following keys. Additional fields such as `commands` or `blocker_type` are allowed.

| Key | Type | Notes |
|-----|------|-------|
| `priority_level` | `1 \| 2 \| 3` | `1` is the highest priority |
| `action` | string | Action kind |
| `description` | string | Human-readable explanation |
| `priority` | `low \| medium \| high` | Display priority |

### Typed Blocker Action Rules

- `resolved = false` and `type = blocker` generates a `priority_level: 1` / `action: "unblock"` entry
- `resolved = false` and `type = dependency` or `issue` generates a `priority_level: 2` / `action: "unblock"` entry
- Legacy string blockers generate a `priority_level: 2` `unblock` entry with `blocker_type: "unknown"`
- When `owner` is present, the generated `unblock` description includes that owner
- `resolved = true` typed blockers do not generate `priority_actions`
- Raw `blocked_by`, `blockers_count`, and score aggregation are unchanged by this contract freeze

### Backward Compatibility

- Plan generation still succeeds when `id` / `summary` / `evidence_refs` are missing, using defaults `""`, `""`, and `[]`
- Plan generation still succeeds when `blocked_by` is a v2 string array
- Plan generation still succeeds when `blocked_by` mixes strings and objects
- Plan generation still tolerates legacy object blockers without `resolved`, treating missing `resolved` as `false` on read

### --format plan Output Example

```json
{
  "id": "ws-feature-auth-20260306",
  "summary": "Waiting on auth flow verification",
  "evidence_refs": ["diff:HEAD~1"],
  "workspace": "feature-auth",
  "branch": "claude/feature-auth",
  "verification_status": "pending",
  "state": "clean",
  "decisions_count": 2,
  "risks_count": 0,
  "blockers_count": 0,
  "blockers": [],
  "score": 72,
  "category": "caution",
  "priority_actions": [
    {
      "priority_level": 2,
      "action": "verify",
      "description": "Please run tests",
      "priority": "medium",
      "commands": ["npm test", "npm run build"]
    },
    {
      "priority_level": 3,
      "action": "review",
      "description": "Please review the considerations",
      "priority": "low"
    }
  ],
  "resume_commands": ["npm test", "npm run build"]
}
```

**Scoring Criteria**:
- `verification_status` (40%): passed=100, skipped=50, pending=30, failed=0, unknown=30
- `state` (20%): clean=100, stash=60, dirty=40, unknown=50
- `blockers_count` (20%): 0=100, 1-2=50, 3+=0
- `risks` (20%): Deduct per risk (low=5, medium=10, high=20, critical=40)

**Category Determination**:
- `ready` (80-100): Ready to start work
- `caution` (50-79): Some considerations needed
- `blocked` (0-49): Blocked, needs resolution

### Examples

```bash
# Resume session as an agent
maw takeover feature-auth

# Check plan information
maw takeover feature-auth --format plan

# Inspect the JSON bundle
maw takeover feature-auth --format json

# Read the Markdown handover
maw takeover feature-auth --format md
```

### Prerequisites

A JSON sidecar must exist (generated by `maw handover` with scope `full` or `summary`).
An error is returned if the JSON file is not found.

---

## `maw merge <name> [options]`

Merge a workspace branch into a target branch.

### Synopsis

```bash
maw merge <name> [--base <branch>] [--no-cleanup] [--dry-run]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<name>` | Workspace name to merge |

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--base <branch>` | Target branch for merge | `main` |
| `--no-cleanup` | Do not remove workspace after merge | false (removes WS) |
| `--dry-run` | Preview only, do not merge | false |

### Examples

```bash
maw merge feature-auth               # merge into main & cleanup
maw merge feature-auth --base develop
maw merge feature-auth --no-cleanup  # keep WS after merge
maw merge feature-auth --dry-run     # preview only
```

### Behavior

1. Check for uncommitted changes in the workspace
2. Run `git merge --no-ff` into the target branch
3. Automatically delete the workspace's claims after success
4. Remove worktree, branch, and handover (unless `--no-cleanup`)
5. Remove the WS entry from `state.json`

---

## `maw cleanup [<name>|--all|--merged] [--dry-run]`

Remove workspaces.

### Synopsis

```bash
maw cleanup [<name>] [--all] [--merged] [--dry-run]
```

### Arguments and Options

| Specifier | Description |
|-----------|-------------|
| `<name>` | Remove a specific workspace |
| `--all` | Remove all workspaces |
| `--merged` | Remove only merged workspaces |
| `--dry-run` | Preview what would be removed (no actual removal) |

### Examples

```bash
maw cleanup feature-auth
maw cleanup --all
maw cleanup --merged
maw cleanup --all --dry-run
```

### What Gets Removed

- git worktree (`.maw-workspaces/<name>/`)
- Branch (only if already merged)
- Handover file (`.maw/handovers/ws-<name>.md`)
- Claims (for this workspace)
- Entry in `state.json`

---

## `maw doctor [options]`

Check environment integrity.

### Synopsis

```bash
maw doctor [--fix] [--aggressive] [--json] [--exit-code-mode simple|multi]
```

### Options

| Option | Description |
|--------|-------------|
| `--fix` | Auto-repair detected issues |
| `--aggressive` | Check merged branches & dangling worktrees (with confirmation prompt when using `--fix`) |
| `--json` | Output results in JSON format (v2 schema, v0.6.0+). Exit codes follow the `--exit-code-mode` contract |
| `--exit-code-mode simple\|multi` | Select exit code policy for `--json` (`simple`: no issues/warning-only=`0`, failed=`1`; `multi`: no issues=`0`, warning-only=`2`, failed=`1`) |

### Checks Performed

| Check | Description | `--fix` action |
|-------|-------------|----------------|
| Orphaned worktree | In state but no worktree on disk | Remove from state |
| Orphaned state | Worktree exists but not in state | Guidance only (`maw cleanup <ws>` is suggested) |
| Symlink integrity | Symlinks point to correct paths | Recreate symlinks |
| Lockfile hash | Lockfile has changed since init | Update saved hash and print reinstall guidance for isolated workspaces |
| Orphaned claim | Claim remains for deleted WS | Delete claim |
| Stale claim | Claim TTL has expired | Delete claim |

### --aggressive Mode Additional Checks

| Check | Description | `--fix` action |
|-------|-------------|----------------|
| Merged branches | Branches already merged to base | Delete worktree & branch with confirmation prompt |
| Dangling worktree | Worktrees removable by git worktree prune | Run git worktree prune |
| Empty handover files | Handover files with zero size | Delete |

### Example Output

```
[WARN] orphaned claim: src/old.ts (workspace: deleted-ws)
[WARN] stale claim: src/auth.ts (expired: 2026-02-20 09:00)
[OK] worktree integrity: OK
[OK] symlink integrity: OK
```

### --json Output Schema (v2, v0.6.0+)

```json
{
  "version": 2,
  "format": "doctor",
  "timestamp": "2026-02-24T10:00:00Z",
  "maw_version": "0.6.0",
  "health_score": 75,
  "summary": {
    "total_checks": 6,
    "passed": 3,
    "failed": 1,
    "warnings": 2,
    "fixable": 3
  },
  "categories": {
    "worktree": {"status": "passed", "score": 100},
    "symlink": {"status": "warning", "score": 70},
    "lockfile": {"status": "passed", "score": 100},
    "git": {"status": "passed", "score": 100},
    "claims": {"status": "failed", "score": 0},
    "stale_claims": {"status": "warning", "score": 80}
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

### `doctor --json` Public Contract

`doctor --json` is a public JSON contract. Key order is not fixed, but the following top-level keys are required.

| Key | Type | Notes |
|-----|------|-------|
| `version` | integer | Currently `2` |
| `format` | string | Currently `"doctor"` |
| `timestamp` | string | UTC timestamp |
| `maw_version` | string | Current `maw` version |
| `health_score` | integer | `floor(sum(categories[*].score) / 6)` |
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

Current scoring rules:
- `passed = 100`
- `failed = 0`
- `warning = 70` for `symlink`, `lockfile`, and `git`
- `warning = 80` for `stale_claims`

`health_score` is the integer average of the 6 category scores:
`floor((worktree + symlink + lockfile + git + claims + stale_claims) / 6)`.

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

### Exit Code Contract

The default mode is `simple`.

| Mode | No issues | Warning only | Failed issues | Invalid mode |
|------|-----------|--------------|---------------|--------------|
| `simple` | 0 | 0 | 1 | 1 |
| `multi` | 0 | 2 | 1 | 1 |

---

## `maw migrate <json-file>`

Migrate handover JSON. The legacy file-path form is kept for backward compatibility, and the preferred T3 flow is `maw migrate handover --to v3`.

### Synopsis

```bash
maw migrate <json-file>
maw migrate handover --to v3 <workspace> [--dry-run|--apply]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<json-file>` | Path to JSON file to migrate |

### Operation

#### Legacy compatibility mode: `maw migrate <json-file>`

1. Verify the JSON file version
2. If the file is `version = 1`, update it to `version = 2`
3. Add the legacy Phase 1 fields (`decisions`, `risks`, `blocked_by`, `resume_commands`, `verification_status`)
4. Overwrite the original JSON file

#### Preferred T3 normalization mode: `maw migrate handover --to v3 <workspace>`

1. Read `.maw/handovers/ws-<workspace>.json`
2. Convert legacy string `blocked_by` entries into typed object blockers
3. Backfill `resolved: false` on converted legacy string blockers and on legacy object blockers that do not have `resolved`
4. Backfill `id`, `summary`, and `evidence_refs` when they are missing
5. Set `version = 3`
6. Skip only when the bundle is already normalized; otherwise normalize in place even if it is already `version: 3`
7. Show a preview by default (`--dry-run`), or overwrite the file with `--apply`

### Examples

```bash
# Legacy v1 -> v2 file migration
maw migrate .maw/handovers/ws-feature-auth.json

# Preferred blocked_by normalization to v3
maw migrate handover --to v3 feature-auth --dry-run
maw migrate handover --to v3 feature-auth --apply

# Verify the migrated version / blockers
cat .maw/handovers/ws-feature-auth.json | jq '.version'
cat .maw/handovers/ws-feature-auth.json | jq '.blocked_by'
```
