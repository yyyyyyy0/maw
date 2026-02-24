# maw Quick Start

## Overview

maw (Multi-Agent Workspace) is a CLI tool for managing parallel workspaces when multiple AI agents work on the same repository.
It leverages git worktrees to create isolated workspaces, providing file claim (exclusive lock) declaration, handover document generation, and branch merge management in a unified interface.

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| git | 2.5+ | brew install git |
| jq | 1.6+ | brew install jq (macOS) / sudo apt install jq (Linux) |
| bash | 3.2+ | usually pre-installed |

## Installation

```bash
git clone https://github.com/yyyyyyy0/maw.git ~/.maw-cli
~/.maw-cli/install.sh
```

Verify installation:

```bash
maw --version
# => maw version 0.4.1
```

## Step 1: Initialize Your Project

```bash
cd your-project
maw init
```

What gets created:

```
your-project/
├── .maw/
│   ├── config.json       # Project configuration
│   ├── state.json        # Workspace state
│   ├── claims.json       # File exclusive claims
│   └── handovers/        # Handover documents
└── .maw-workspaces/      # worktree root
```

The ecosystem (Node.js / Python / Rust / Go) is detected automatically.
`.maw/` and `.maw-workspaces/` are added to `.gitignore` automatically.

## Step 2: Create a Workspace

```bash
# Basic
maw spawn feature-auth

# With agent name and issue number
maw spawn feature-auth --agent claude --issue 42

# With a specific base branch
maw spawn feature-auth --agent claude --from develop
```

After creation, a worktree is available at `.maw-workspaces/feature-auth/`.
For Node.js projects, `node_modules` is shared via symlink (saves disk space).

## Step 3: Check Current Status

```bash
maw status
```

Example output:

```
=== Workspaces ===
     NAME             BRANCH                    AGENT    ISSUE   CREATED
  -----------------------------------------------------------------------
  -> feature-auth     claude/feature-auth       claude   42      2026-02-24

=== Claims ===
  FILE                     WORKSPACE       AGENT    CLAIMED       EXPIRES
  -----------------------------------------------------------------------
  (none)
```

`->` indicates the workspace that corresponds to the current working directory.

## Step 4: Claim Files Before Editing

**Always** run `maw claim` before editing any file. This prevents conflicts with other agents.

```bash
# Claim a file
maw claim src/auth.ts

# Claim a directory
maw claim src/components/

# Claim with TTL (expires in 90 minutes)
maw claim src/auth.ts --ttl 90
```

If another workspace already holds a claim, you get an error:

```
✗ src/auth.ts is already claimed by feature-login (agent: claude)
```

## Step 5: Implement

Work normally inside the workspace's worktree directory (`.maw-workspaces/feature-auth/`).

When done with a file:

```bash
maw unclaim src/auth.ts  # release the claim
```

## Step 6: Generate a Handover Document

After completing work, generate a handover document for the next agent or human:

```bash
maw handover
```

This creates `.maw/handovers/ws-feature-auth.md` containing:

- Branch info, agent name, and issue number
- Commit history (latest 20 entries)
- Changed file list
- Uncommitted changes
- Claims state
- Notes (free-form placeholder)

## Step 7: Merge the Branch

```bash
# Merge into main (with auto cleanup)
maw merge feature-auth

# Specify target branch
maw merge feature-auth --base develop

# Keep workspace after merge
maw merge feature-auth --no-cleanup

# Dry run (preview only)
maw merge feature-auth --dry-run
```

After a successful merge, the workspace's claims are automatically deleted.

## Step 8: Cleanup

```bash
maw cleanup feature-auth        # Remove a specific WS
maw cleanup --merged            # Remove all merged workspaces
maw cleanup --all               # Remove all workspaces
maw cleanup --all --dry-run     # Preview what would be removed
```

## Health Check

```bash
maw doctor       # Detect issues
maw doctor --fix # Auto-repair
```

doctor checks:

- Orphaned worktrees (in state but no worktree on disk)
- Broken symlinks
- Lockfile changes (dependency drift)
- Orphaned claims (WS deleted but claim remains)
- Expired claims (TTL exceeded)

## Typical Agent Workflow

```bash
# 1. Check current status
maw status

# 2. Create workspace (first time only)
maw spawn my-feature --agent claude --issue 123

# 3. Claim files before editing
maw claim src/target-file.ts

# 4. Implement...

# 5. Generate handover
maw handover

# 6. Merge & cleanup
maw merge my-feature
```

## Next Steps

- [Command Reference](commands.md) — Detailed options for all commands
- [Configuration Reference](config.md) — config.json and settings
- [Concepts](concepts.md) — WS / claim / handover design philosophy
