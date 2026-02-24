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
| `--from <branch>` | Base branch to create worktree from | current branch |

### Examples

```bash
maw spawn feature-auth
maw spawn feature-auth --agent claude
maw spawn feature-auth --issue 42
maw spawn feature-auth --agent claude --issue 42  # branch: claude/feature-auth
maw spawn feature-auth --isolated                 # independent node_modules
maw spawn feature-auth --from develop             # branch from develop
```

### Behavior

1. Create a git worktree on the specified branch
2. Check out to `.maw-workspaces/<name>/`
3. Create symlinks per ecosystem config (skipped with `--isolated`)
4. Register workspace info in `state.json`

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

Generate a handover document.

### Synopsis

```bash
maw handover [--workspace <name>]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--workspace <name>` | Explicitly specify workspace name | auto-detect from current dir |

### Output

`.maw/handovers/ws-<name>.md`

### Content Generated

- Workspace info (branch, agent, issue)
- Commit history (`git log --oneline`, latest 20)
- Changed files (`git diff --name-status`)
- Uncommitted changes (`git status --short`)
- Claims list (for this workspace only)
- Notes (free-form placeholder)

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

## `maw doctor [--fix]`

Check environment integrity.

### Synopsis

```bash
maw doctor [--fix]
```

### Options

| Option | Description |
|--------|-------------|
| `--fix` | Auto-repair detected issues |

### Checks Performed

| Check | Description | `--fix` action |
|-------|-------------|----------------|
| Orphaned worktree | In state but no worktree on disk | Remove from state |
| Orphaned state | Worktree exists but not in state | Add to state |
| Symlink integrity | Symlinks point to correct paths | Recreate symlinks |
| Lockfile hash | Lockfile has changed since init | Warn only |
| Orphaned claim | Claim remains for deleted WS | Delete claim |
| Stale claim | Claim TTL has expired | Delete claim |

### Example Output

```
[WARN] orphaned claim: src/old.ts (workspace: deleted-ws)
[WARN] stale claim: src/auth.ts (expired: 2026-02-20 09:00)
[OK] worktree integrity: OK
[OK] symlink integrity: OK
```
