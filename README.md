# maw

**Repo-local coordination contract for parallel coding agents**

maw is a lightweight CLI for safe parallel coding operations in a single repository. It uses git worktrees underneath, but the value is the contract layer on top: `claim` for collision prevention, `handover` for canonical work-state bundles, `takeover` for deterministic resume plans, and `doctor --json` for machine-readable health gates.

マルチエージェント開発（Claude Code, Codex 等）で、並列作業の事故率を下げて再開可能性を上げるための CLI です。`git worktree` は実装手段であり、価値の中心は `claim` / `handover` / `takeover` / `doctor` が作る運用契約にあります。

## What maw provides

| Need | maw contract |
|---|---|
| Prevent edit collisions before merge time | `maw claim` declares exclusive ownership on shared paths |
| Preserve work state across sessions | `maw handover` writes a Markdown view plus a JSON bundle |
| Resume work safely with machine-readable guidance | `maw takeover --format plan` returns `ready/caution/blocked`, score, blockers, and `priority_actions` |
| Gate automation and CI on repo health | `maw doctor --json --exit-code-mode multi` returns a stable health contract |
| Keep workspace lifecycle controlled | `maw spawn`, `maw merge`, and `maw cleanup` manage isolated workspaces |

## Install

```bash
git clone https://github.com/yyyyyyy0/maw.git ~/.maw-cli
~/.maw-cli/install.sh
```

**Required tools**: `git`, `jq`

```bash
# macOS
brew install jq

# Linux (Debian/Ubuntu)
sudo apt install jq
```

## Quick Start

```bash
# 1. Initialize the repository
cd your-project
maw init

# 2. Create an isolated workspace from the latest origin/main
maw spawn feature-auth --agent claude --issue 42
# If --from is omitted, maw fetches origin/main and fails if it cannot resolve it.

# 3. Check current state and claim the file before editing
maw status
maw claim src/auth.ts

# 4. Do the work, then create a handover bundle
maw handover --workspace feature-auth
maw handover --workspace feature-auth \
  --summary "JWT migration is implemented and waiting for verification." \
  --verification-status pending \
  --resume-command "bats tests/e2e_test.bats" \
  --evidence-ref "diff:HEAD~1" \
  --evidence-ref "test:bats tests/e2e_test.bats"

# 5. Read the machine-readable resume plan
maw takeover feature-auth --format plan | jq '{workspace, category, score, priority_actions}'

# 6. Run the health gate used by CI/automation
maw doctor --json --exit-code-mode multi | jq '{health_score, summary}'

# 7. Merge when the plan is ready and the repo is healthy
maw merge feature-auth
```

`maw handover` produces:

- `.maw/handovers/ws-<name>.md` for people
- `.maw/handovers/ws-<name>.json` for `maw takeover`, automation, and audit trails

In practice, the JSON sidecar is the canonical handover bundle. Markdown is the human-readable projection.

## Contract Surfaces

| Command | Primary role |
|---|---|
| `maw claim <path>` | Declare exclusive ownership before editing a shared file or directory |
| `maw handover` | Generate and enrich the canonical work-state bundle |
| `maw takeover [<name>] --format plan` | Produce a deterministic resume/readiness plan with `score`, `category`, `blockers`, and `priority_actions` |
| `maw takeover [<name>] --format json` | Read the raw handover bundle for scripts and integrations |
| `maw doctor --json --exit-code-mode multi` | Expose a versioned health contract for CI and automation |
| `maw merge <name>` | Merge through maw so claims and workspace lifecycle stay consistent |

`takeover --format md` and `takeover --format prompt` remain useful supporting views, but `plan` and `json` are the contract-centered outputs for resume automation.

## Command Overview

| Command | Description |
|---------|-------------|
| `maw init` | Initialize `.maw/`, workspace state, and claim storage |
| `maw spawn <name>` | Create an isolated workspace from `origin/main` or `--from` |
| `maw list` | Show every managed workspace |
| `maw status` | Show workspaces and active claims in one view |
| `maw claim <path>` | Claim a file or directory before editing |
| `maw unclaim <path>` | Release a claim when the path is no longer actively edited |
| `maw handover` | Generate or update a Markdown + JSON handover bundle |
| `maw takeover [<name>]` | Read a handover bundle as `md`, `json`, `prompt`, or `plan` |
| `maw doctor` | Run repo health checks, including JSON output for CI gates |
| `maw merge <name>` | Merge a workspace branch through maw-managed cleanup |
| `maw cleanup` | Remove workspaces and stale maw-managed artifacts |

## Documentation

| Document | Description |
|------------|-------------|
| [Quick Start (Japanese)](docs/ja/getting-started.md) | Contract-first setup and daily workflow |
| [Quick Start (English)](docs/en/getting-started.md) | Contract-first setup and daily workflow |
| [Command Reference (Japanese)](docs/ja/commands.md) | Full CLI options and output contracts |
| [Command Reference (English)](docs/en/commands.md) | Full CLI options and output contracts |
| [Doctor CI Guide (Japanese)](docs/ja/doctor-ci.md) | Using `maw doctor --json` as a CI gate |
| [Doctor CI Guide (English)](docs/en/doctor-ci.md) | Using `maw doctor --json` as a CI gate |
| [Configuration Reference (Japanese)](docs/ja/config.md) | `config.json` and project settings |
| [Configuration Reference (English)](docs/en/config.md) | `config.json` and project settings |
| [Concepts (Japanese)](docs/ja/concepts.md) | Workspace / claim / handover design ideas |
| [Concepts (English)](docs/en/concepts.md) | Workspace / claim / handover design ideas |

## For Agents

When maw is used by an AI coding agent:

- `SKILL.md` defines the maw workflow for agents
- `AGENTS.md` defines the core operating rules
- `AGENTS.extensions.md` defines maw-specific workspace rules

The intended loop is:

```bash
maw status
maw spawn <name> --agent <agent> --issue <n>
maw claim <path>
# implement
maw handover
maw takeover <name> --format plan
maw doctor --json --exit-code-mode multi
maw merge <name>
```

## License

MIT
