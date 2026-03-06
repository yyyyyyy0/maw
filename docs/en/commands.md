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
| `--blocked-by <text>` | Add to blocked_by array (record factors blocking work) |

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
  "blocked_by": ["External API specification"],
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

### Backward Compatibility

- Plan generation still succeeds when `id` / `summary` / `evidence_refs` are missing, using defaults `""`, `""`, and `[]`
- Plan generation still succeeds when `blocked_by` is a v2 string array
- Plan generation still succeeds when `blocked_by` mixes strings and objects

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
maw doctor [--fix] [--aggressive] [--json]
```

### Options

| Option | Description |
|--------|-------------|
| `--fix` | Auto-repair detected issues |
| `--aggressive` | Check merged branches & dangling worktrees (with confirmation prompt when using `--fix`) |
| `--json` | Output results in JSON format (v2 schema, v0.6.0+). Exits with non-zero when issues are detected |

### Checks Performed

| Check | Description | `--fix` action |
|-------|-------------|----------------|
| Orphaned worktree | In state but no worktree on disk | Remove from state |
| Orphaned state | Worktree exists but not in state | Add to state |
| Symlink integrity | Symlinks point to correct paths | Recreate symlinks |
| Lockfile hash | Lockfile has changed since init | Warn only |
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
  "health_score": 85,
  "summary": {
    "total_checks": 6,
    "passed": 4,
    "failed": 1,
    "warnings": 1,
    "fixable": 1
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

**Field Descriptions**:
- `health_score`: Overall health score (0-100, average of category scores)
- `categories`: Status and score per category
  - `status`: passed / warning / failed
  - `score`: 0-100 (failed=0, warning=70, passed=100)
- `checks[].category`: Category each check belongs to

---

## `maw migrate <json-file>`

Migrate handover JSON from v1 to v2.

### Synopsis

```bash
maw migrate <json-file>
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<json-file>` | Path to JSON file to migrate |

### Operation

1. Verify JSON file version
2. If version 1, update to version 2
3. Add the following fields (initialized with empty arrays/default values):
   - `decisions`: []
   - `risks`: []
   - `blocked_by`: []
   - `resume_commands`: []
   - `verification_status`: "pending"
4. Overwrite the original JSON file

### Examples

```bash
# Migrate handover JSON from v1 to v2
maw migrate .maw/handovers/ws-feature-auth.json

# Verify the migrated version
cat .maw/handovers/ws-feature-auth.json | jq '.version'
# Output: 2
```
