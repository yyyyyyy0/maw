
## Multi-Agent Workspace (maw)

This workspace is managed by `maw`.

### Rules

- **File exclusion**: Run `maw claim <file>` before working on files
- **State sharing**: Run `maw handover` when completing work to generate handover docs
- **Dependencies**: `node_modules/` is a symlink. Run package install in the main project
- **Branch**: You are working on a dedicated branch for this workspace

### Commands

```bash
maw status          # Check all workspace status
maw claim <file>    # Claim file exclusivity
maw unclaim <file>  # Release file claim
maw handover        # Generate handover document
```
