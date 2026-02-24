# Concepts

## Why maw Exists

When multiple AI agents work on the same repository in parallel, several problems arise:

1. **File conflicts**: Two agents edit the same file simultaneously
2. **Context fragmentation**: One agent doesn't know what another is working on
3. **Lifecycle sprawl**: Creating, deleting, and merging worktrees is uncoordinated

maw solves these through three primitives: **Workspace management**, **Claim (exclusive lock) declaration**, and **Handover (context transfer)**.

---

## Workspace

### Concept

A Workspace is an **isolated unit of work**. It is implemented as a git worktree, allowing each agent to have its own branch while sharing large dependency directories.

```
repo-root/
├── .maw-workspaces/
│   ├── feature-auth/     <- agent-A's workspace (git worktree)
│   │   ├── src/          (own files)
│   │   └── node_modules  -> ../../node_modules  (symlink: shared)
│   └── bugfix-login/     <- agent-B's workspace (git worktree)
│       ├── src/          (own files)
│       └── node_modules  -> ../../node_modules  (symlink: shared)
└── node_modules/         <- single source of truth (shared by all)
```

### Design Principles

- **1 agent = 1 workspace**: Parallel agents always use separate workspaces
- **Branch isolation**: Each workspace works on an independent branch
- **Dependency sharing**: Large directories like `node_modules` are symlinked to save disk space
- **Centralized metadata**: The `.maw/` directory manages state for all workspaces

### Lifecycle

```
maw spawn  →  work  →  maw handover  →  maw merge  →  maw cleanup
   ↑                                                        |
   └────────────────────────────────────────────────────────┘
               (create new WS if needed)
```

---

## Claim (Exclusive Lock)

### Concept

A Claim is a declaration of **"I am working on this file."** It is the concrete implementation of AGENTS.md rule R-COLLAB-001: "Parallel work MUST be assumed and conflict risk checked before shared-file edits."

### Why Git Alone Is Not Enough

Git detects conflicts at merge time, but it **cannot prevent conflicts in real time while work is in progress**. Two agents editing the same file in parallel discover the conflict only when they try to merge. maw's Claim system detects conflicts **before work begins**.

### Claim Conflict Rules

```
Before editing file F, run: maw claim F

Check 1: F is already claimed by another WS → Error
Check 2: A parent directory of F is claimed by another WS → Error
Check 3: F is a directory, and a child path is claimed by another WS → Error
Check 4: Same WS re-claims same path → Idempotent (update)
Check 5: Claim over an expired claim → Success
```

### TTL (Time-to-Live)

Claims support an optional expiry (TTL), added in v0.4.0.

```bash
maw claim src/auth.ts --ttl 90   # expires in 90 minutes
```

- TTL stores an `expires_at` timestamp
- Expired claims can be auto-cleaned by `maw doctor --fix`
- Subsequent agents can override expired claims

TTL purposes:

1. **Dead agent protection**: Prevents claims from persisting if an agent crashes
2. **Guard window signaling**: Communicates "don't touch this for N minutes"

### Claim Scope

| Scope | Example | Description |
|-------|---------|-------------|
| File | `src/auth.ts` | Exclusive lock on a single file |
| Directory | `src/components/` | Exclusive lock on all files under a directory |

Directory claims are appropriate for coarse-grained "I own this feature area" declarations.

---

## Handover (Context Transfer)

### Concept

A Handover is a **context transfer package**. When an agent pauses or completes work, it generates a document that allows the next agent (or human) to resume work with full context.

### Design Motivation

AI agents cannot retain context across sessions. There is also no mechanism for agent A to "tell" agent B what it has done. Handover fills this gap.

### Generated Content

```markdown
# Handover: feature-auth

## Workspace Info
(branch, agent, issue)

## Recent Commits
(git log --oneline)

## Changed Files
(git diff --name-status)

## Uncommitted Changes
(git status --short)

## Claims
(claims held by this WS)

## Notes
(free-form notes)
```

### Handover Usage Patterns

**Pattern A: Agent handoff**
```
agent-A: maw handover  → generates .maw/handovers/ws-feature.md
agent-B: reads .maw/handovers/ws-feature.md → continues work
```

**Pattern B: Human progress review**
```
agent: maw handover  → generates .maw/handovers/ws-feature.md
human: reads the file → reviews progress
```

**Pattern C: Pre-merge record**
```
agent: maw handover  → records context before merge
agent: maw merge feature  → merges the branch
```

---

## Ecosystem Generalization (v0.4.0)

maw was originally designed for Node.js projects but v0.4.0 extended it to other ecosystems.

### Ecosystem Detection

`maw init` inspects the repository root to determine the ecosystem:

| Detected file | Ecosystem |
|--------------|-----------|
| `package.json` | `nodejs` |
| `pyproject.toml` / `requirements.txt` | `python` |
| `Cargo.toml` | `rust` |
| `go.mod` | `go` |
| (none of the above) | `generic` |

### Default Symlinks per Ecosystem

| Ecosystem | Default symlinks |
|----------|-----------------|
| `nodejs` | `node_modules` |
| `rust` | `target` |
| `python` / `go` / `generic` | none |

Override via `symlinkDirs` in `config.json`.

---

## Atomic Writes

`state.json` and `claims.json` are updated using atomic writes (`mktemp` + `mv`). This means:

- Crashes during writes cannot corrupt the file
- No other process reads a half-written file

This improves safety when parallel agents update state simultaneously. However, maw does not implement a strict lock mechanism — that is why **pre-edit Claim declaration is essential**.

---

## maw and R-COLLAB-001

AGENTS.md rule R-COLLAB-001 states:

> "Parallel work MUST be assumed and conflict risk checked before shared-file edits."

maw is the **concrete infrastructure** for this rule:

- `maw claim` = conflict risk check and declaration
- `maw status` = view current conflict state
- `maw handover` = transfer work context
- `maw merge` = controlled branch integration

Agents MUST NOT edit shared files without first running `maw claim` (see R-MAW-CLAIM-001 in `AGENTS.extensions.md`).

---

## Design Philosophy

### Bash-only, Minimal Dependencies

No additional runtime (Node.js, Python, etc.) is required. maw runs on bash, `git`, and `jq` only. This ensures:

- Works in any CI/CD environment
- Easy installation
- Transparent, readable scripts

### macOS + Linux Compatibility

Portable bash syntax and dual macOS/GNU `date` support (TZ=UTC) ensure cross-platform operation.

### Idempotency

All operations are designed to be idempotent wherever possible. Running the same command twice is safe.
