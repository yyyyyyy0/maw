# AGENTS.v2
This file defines the core, always-on operating rules for coding agents.

## 1. Purpose
### R-PURPOSE-001 (MUST)
- Changes MUST be correct, safe, minimal, and verifiable.
### R-PURPOSE-002 (MUST)
- Rule conflicts MUST be resolved by precedence.

## 2. Normative Keywords
### R-NORM-001 (MUST)
- `MUST` is mandatory. Exceptions are limited to explicit `Exception:` conditions.
### R-NORM-002 (MUST)
- Any `SHOULD` deviation MUST include reason in the same report.
### R-NORM-003 (MUST)
- When `MAY` is used, impact scope MUST be explicit.

## 3. Rule Precedence
### R-PRIORITY-001 (MUST)
- Fixed order MUST be: User instruction > Nearest AGENTS > Repo root AGENTS > Other instruction files.
### R-PRIORITY-002 (MUST)
- Superseded rules MUST be stated in report.

## 4. Execution Loop
### R-LOOP-001 (MUST)
- Execution order MUST be `read -> plan -> run -> verify -> report`.
- Step definitions: `read` = inspect instructions; `plan` = outline steps; `run` = execute; `verify` = check results; `report` = summarize.
### R-LOOP-002 (MUST)
- `read` MUST inspect nearest instructions and relevant references.
### R-LOOP-READ-001 (MUST)
- Before `plan`, `read` MUST establish project structure: inspect directory layout, entry points, and dependency manifests relevant to the task scope.
### R-LOOP-FRESH-001 (MUST)
- `read` MUST use current file state; training-time knowledge MUST NOT substitute for live file inspection when files are accessible.
### R-LOOP-003 (MUST)
- `report` MUST NOT be emitted before `verify`.
### R-LOOP-FAIL-001 (MUST)
- When `verify` fails, execution MUST NOT proceed to `report`; instead, return to `run` with a corrective action or escalate to the user if the required fix expands task scope.
### R-LOOP-PLAN-TRIGGER-001 (MUST)
- Plan trigger MUST use two-axis criteria: complexity OR risk.
### R-LOOP-PLAN-TRIGGER-002 (MUST)
- Complexity includes dependency coupling, 3+ steps, or architectural decision.
### R-LOOP-PLAN-TRIGGER-003 (MUST)
- Risk includes auth impact, data-loss risk, external blast radius, or hard rollback.

## 5. Scope Control
### R-SCOPE-001 (MUST)
- Files unrelated to the requested outcome MUST NOT be changed.
### R-SCOPE-002 (MUST)
- Unrelated fixes/formatting/refactors MUST NOT be bundled into the same task.
### R-SCOPE-003 (MUST)
- Dependency additions, public API changes, and cross-cutting refactors MUST be confirmed before execution.
### R-SCOPE-CLARIFY-001 (MUST)
- When requirements are ambiguous or underspecified, clarification MUST be sought before entering `run`. Assumptions MUST NOT substitute for explicit instruction.

## 6. Verification Gates
### R-VERIFY-001 (MUST)
- After changes, minimally sufficient checks MUST run and be recorded in `verify`.
### R-VERIFY-002 (MUST)
- Wide-impact changes MUST include staged broader validation.
### R-VERIFY-003 (MUST)
- Skipped checks MUST include item, reason, and alternative evidence.
### R-VERIFY-LEVEL-001 (MUST)
- Bug fixes MUST satisfy all of the following with evidence:
  - `reproduce`: confirm the defect is reproducible
  - `fix`: apply the correction
  - `regression`: verify no existing tests break
  - `log check`: confirm runtime logs show no new errors
### R-VERIFY-LEVEL-002 (MUST)
- Feature additions MUST satisfy all of the following:
  - `acceptance`: validate against acceptance criteria
  - `tests`: pass new and existing tests
  - `compatibility`: confirm backward compatibility
  - `delta explanation`: document what changed and why
### R-VERIFY-EVIDENCE-001 (MUST)
- Verification output MUST include at least one of:
  - test names (passing assertions)
  - logs (runtime or CI output)
  - comparison targets (before/after diff or baseline reference)

## 7. Security Baseline
### R-SEC-001 (MUST)
- Secrets/tokens/credentials MUST NOT be committed, output, or shared.
### R-SEC-002 (MUST)
- `.env` and equivalent secret files MUST NOT be edited without explicit instruction.
### R-SEC-003 (MUST)
- External input MUST be validated and outputs handled safely by context.

## 8. Git Safety
### R-GIT-001 (MUST)
- Destructive rollback (`git reset --hard`, unsafe `git restore`, equivalents) MUST NOT run without explicit instruction.
### R-GIT-002 (MUST)
- In-flight work by others MUST NOT be reverted/deleted without coordination.
### R-GIT-003 (MUST)
- Change scope MUST be checked via `git status` equivalent before commit.
### R-GIT-004 (MUST)
- Commit amend MUST NOT be used unless explicitly instructed.

## 9. Collaboration Rules
### R-COLLAB-001 (MUST)
- Parallel work MUST be assumed and conflict risk checked before shared-file edits.
### R-COLLAB-002 (MUST)
- Unexpected diffs MUST trigger pause until intent is confirmed.
### R-COLLAB-SUBAGENT-MERGE-001 (MUST)
- Subagent merge output MUST follow a fixed four-section format: `conclusion / evidence / unknowns / recommended next action`.
- Each section MUST be explicitly labeled and non-empty.
### R-COLLAB-SUBAGENT-BUDGET-001 (SHOULD)
- Concurrent subagents SHOULD start with cap 2-3 and avoid duplicate investigation.

## 10. Completion Criteria
### R-DONE-001 (MUST)
- Completion MUST be declared only when implementation, verification, and reporting are complete.
### R-DONE-002 (MUST)
- Completion report MUST list changed files, executed validation, and skipped items.

## 11. Report Contract
### R-REPORT-001 (MUST)
- `report` MUST use the following fixed section order: `What changed -> Why -> Verify results -> Risks/next actions`.
- Each section MUST be explicitly labeled; omitting a section requires a stated reason.
### R-REPORT-002 (MUST)
- Any `SHOULD` deviation MUST include reason in the same report.
### R-REPORT-LESSON-001 (SHOULD)
- Lesson file updates SHOULD use `symptom / cause / prevention` in 3 lines. Target file is defined per-repo (default: `tasks/lessons.md`).
### R-REPORT-LESSON-002 (MUST)
- Each lesson entry MUST include at least one Rule ID or file reference.
### R-AUTONOMY-GUARD-001 (MUST)
- Autonomous bug fixing is allowed, but pre-execution confirmation is MUST for destructive/public-contract/data-loss-risk changes.

## 12. Extensions
For Skill design, Contract strictness, Hands-on E2E, and Team orchestration details, refer to `AGENTS.extensions.md`. Extension rules are active only within their respective contexts. In conflicts, core-file precedence (`R-PRIORITY-*`) takes priority.
