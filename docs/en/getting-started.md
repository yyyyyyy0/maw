# maw Quick Start

## Overview

maw (Multi-Agent Workspace) is a CLI for safe parallel work in a single repository. It uses `git worktree` underneath, but the main value is the operating contract on top of it.

- `maw claim` prevents edit collisions before they become merge conflicts
- `maw handover` writes a Markdown view plus a JSON bundle
- `maw takeover --format plan` turns that bundle into `ready / caution / blocked` plus `priority_actions`
- `maw doctor --json` provides a machine-readable health gate for CI and automation

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
# => maw v0.9.0
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
│   ├── claims.json       # File claims
│   └── handovers/        # Handover bundles
└── .maw-workspaces/      # git worktree root
```

The ecosystem (Node.js / Python / Rust / Go) is detected automatically. `.maw/` and `.maw-workspaces/` are added to `.gitignore` for you.

## Step 2: Create a Workspace

```bash
# Basic
maw spawn feature-auth

# With agent name and issue number
maw spawn feature-auth --agent claude --issue 42

# With an explicit base branch
maw spawn feature-auth --agent claude --from develop
```

If `--from` is omitted, `maw spawn` fetches `origin/main` and uses the latest resolved commit as the base branch. If `origin/main` cannot be fetched or resolved, the command fails with no fallback.

The workspace lives at `.maw-workspaces/feature-auth/`. The worktree is the isolation mechanism; the contract workflow starts with the next steps.

## Step 3: Check Status and Claim Files

```bash
maw status
maw claim src/auth.ts
```

Always claim a shared path before editing it. That lets maw stop collisions before another agent touches the same file or directory.

Claims can also use TTL:

```bash
maw claim src/auth.ts --ttl 90
```

## Step 4: Generate a Handover Bundle

First generate the baseline bundle:

```bash
maw handover --workspace feature-auth
```

Then enrich it with the structured fields the next agent or automation run will need:

```bash
maw handover --workspace feature-auth \
  --summary "JWT migration is complete and waiting for verification." \
  --verification-status pending \
  --resume-command "bats tests/e2e_test.bats" \
  --evidence-ref "diff:HEAD~1" \
  --evidence-ref "test:bats tests/e2e_test.bats"
```

Generated outputs:

- `.maw/handovers/ws-feature-auth.md`
  - human-readable handover view
- `.maw/handovers/ws-feature-auth.json`
  - canonical bundle used by `takeover`, automation, and audits

The JSON sidecar carries `summary`, `verification_status`, `resume_commands`, `evidence_refs`, `blocked_by`, `risks`, `decisions`, and the rest of the structured work state.

## Step 5: Read the Takeover Plan

`maw takeover --format plan` converts the handover bundle into a deterministic resume plan.

```bash
maw takeover feature-auth --format plan | jq '{workspace, category, score, blockers, priority_actions}'
```

Important fields:

- `category`: `ready | caution | blocked`
- `score`: readiness score from 0 to 100
- `blockers`: up to 3 normalized blocker summaries
- `priority_actions`: the next actions to take

Supporting views:

```bash
maw takeover feature-auth --format json
maw takeover feature-auth --format md
maw takeover feature-auth --format prompt
```

Use `plan` and `json` as the contract-centered outputs. `md` and `prompt` are supporting projections for people and model prompts.

## Step 6: Run the Doctor Health Gate

For CI and automation, use `doctor --json` as the health contract:

```bash
maw doctor --json --exit-code-mode multi | jq '{health_score, summary, categories}'
```

`--exit-code-mode multi` means:

- `0`: no issues
- `2`: warnings only
- `1`: failed issues present

That makes it easy to distinguish warnings from blocking failures in automation.

## Step 7: Merge the Workspace

```bash
maw merge feature-auth
```

You can also use:

```bash
maw merge feature-auth --base develop
maw merge feature-auth --dry-run
maw merge feature-auth --no-cleanup
```

Using `maw merge` keeps claims and workspace cleanup under maw control.

## Typical Daily Workflow

```bash
# 1. Check current state
maw status

# 2. Create a workspace
maw spawn my-feature --agent claude --issue 123

# 3. Claim the file before editing
maw claim src/target-file.ts

# 4. Implement...

# 5. Update the handover bundle
maw handover --workspace my-feature
maw handover --workspace my-feature \
  --summary "API implementation is complete. Waiting for E2E verification." \
  --verification-status pending \
  --resume-command "bats tests/e2e_test.bats" \
  --evidence-ref "diff:HEAD~1"

# 6. Inspect the resume plan and health gate
maw takeover my-feature --format plan
maw doctor --json --exit-code-mode multi

# 7. Merge
maw merge my-feature
```

## Next Documents

- [Command Reference](commands.md) — detailed CLI options and output contracts
- [Configuration Reference](config.md) — `config.json` and project settings
- [Concepts](concepts.md) — background on workspace / claim / handover
- [Doctor CI Guide](doctor-ci.md) — using `maw doctor --json` in CI
