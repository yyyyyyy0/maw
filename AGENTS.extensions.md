# AGENTS.extensions
This file defines context-specific extension rules for SKILL schema, contract design, hands-on E2E, and team orchestration.

## 1. Skill Schema Rules
### R-SKILL-SCHEMA-001 (MUST)
- All SKILL docs MUST use the same header keys (`name/description/allowed-tools/inputs/outputs/constraints/steps`).
### R-SKILL-SCHEMA-002 (MUST)
- Markdown tables MUST use proper pipe-table syntax.

## 2. Contract Strictness Rules
### R-CONTRACT-SEM-001 (MUST)
- `NotFound` semantics MUST be singular; `None/null` and `NotFound error` MUST NOT coexist.
### R-CONTRACT-SEM-002 (MUST)
- Cross-language differences (context/cancel/timeout/trace) MUST be explicit via shared contract or language-delta table.
### R-CONTRACT-TEST-001 (MUST)
- Contract tests MUST include conflict behavior, upsert/create-only semantics, error mapping, and ordering/consistency requirements.

## 3. Hands-on E2E Rules
### R-E2E-PREFLIGHT-001 (MUST)
- Preflight MUST verify CLI availability, browser install state, and headless/headful mode.
### R-E2E-CONFIG-001 (MUST)
- `BASE_URL` MUST be required input; hardcoded ports (for example `:3000`) are prohibited. Use environment variables instead.
### R-E2E-CONFIG-002 (MUST)
- Auth/session/seed policy MUST be explicit (cookie/storage state, test user, no secret leakage in reports).
### R-E2E-PREFLIGHT-002 (MUST)
- Dev-server command discovery MUST define fixed priority and fallback order on failure.
### R-E2E-PORTABLE-001 (SHOULD)
- Screenshot validation SHOULD be tool-agnostic and expressed as capability requirements.

## 13. maw Workspace Rules
### R-MAW-INIT-001 (MUST)
- If `.maw/` exists in the repository, run `maw status` before starting any work to understand the current workspace and claim state.

### R-MAW-CLAIM-001 (MUST)
- Before editing any file that may be shared with parallel agents, run `maw claim <file>`.
- If a claim conflict occurs (another workspace already holds the claim), stop editing and report to the user with: the conflicting file path, the workspace name, the agent name, and the expiry time.
- This is the concrete implementation of R-COLLAB-001.

### R-MAW-CLAIM-UNCLAIM-001 (SHOULD)
- Release claims via `maw unclaim` when a file is no longer being actively edited, to minimize the lock surface area for other agents.

### R-MAW-DONE-001 (MUST)
- When work is complete, run `maw handover` to generate a handover document before closing the session.

### R-MAW-MERGE-001 (MUST)
- Branch merges MUST go through `maw merge`. Direct `git merge` bypasses claim cleanup and workspace lifecycle management.

### R-MAW-DOCTOR-001 (SHOULD)
- Run `maw doctor` at the start of a session when `.maw/` exists. Run `maw doctor --fix` when integrity issues are detected before beginning work.

## 4. Team Orchestration Rules
### R-TEAM-EXEC-001 (MUST)
- Environment-dependent steps (commit/diagram commit) MUST be conditional.
### R-TEAM-EXEC-002 (MUST)
- `$ARGUMENTS` MUST define scope, acceptance criteria, and constraints; these values are supplied in the skill/team header.
### R-TEAM-EXEC-003 (SHOULD)
- Text quality (including typo fixes) SHOULD be part of minimum quality gates.

## 5. Extension Validation Scenarios
### R-TEST-004 (MUST)
- Scenario: A module returns `None` on missing record AND raises a `NotFoundError` in the same interface.
- Expected: Validation fails; dual `NotFound` semantics MUST be flagged.

### R-TEST-005 (MUST)
- Scenario: E2E preflight runs with Playwright CLI missing, browser not installed, and headless mode unset.
- Expected: Each condition is detected and reported before any test execution begins.

### R-TEST-006 (MUST)
- Scenario: A SKILL document is missing the `constraints` header key.
- Expected: Validation reports a header-key inconsistency and fails.

### R-TEST-007 (MUST)
- Scenario: A team orchestration procedure contains a commit step with no execution condition.
- Expected: Validation flags the unconditional environment-dependent step.
