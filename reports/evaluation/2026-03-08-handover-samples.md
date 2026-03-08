# Handover Samples (2026-03-08)

Operationally derived handover samples promoted into tracked evaluation artifacts.
Tracked copies intentionally exclude volatile fields such as claims, raw logs, and raw diffs.

| sample | workspace | verification_status | evidence_refs | notes |
| --- | --- | --- | ---: | --- |
| ws-issue10_t2_docs | issue10_t2_docs | skipped | 4 | summary/evidence_refs present |
| ws-issue10_t3_pr | issue10_t3_pr | passed | 3 | summary/evidence_refs present |
| ws-issue10_t6_pr | issue10_t6_pr | skipped | 3 | summary/evidence_refs present |

## ws-issue10_t2_docs

Workspace: issue10_t2_docs

Summary: Issue 10 T2 docs: fixed the public doctor --json contract in commands and CI docs, including a new English doctor-ci guide

Evidence refs:
- docs:docs/ja/commands.md
- docs:docs/en/commands.md
- docs:docs/ja/doctor-ci.md
- docs:docs/en/doctor-ci.md

Verification status: skipped


## ws-issue10_t3_pr

Workspace: issue10_t3_pr

Summary: T3: froze the typed blocked_by contract in commands docs, validate_handover_bundle, and regression tests while keeping legacy read compatibility.

Evidence refs:
- test:bats tests/maw_test.bats --filter blocked_by|takeover --format plan|handover --validate|migrate handover
- test:bats tests/maw_test.bats --filter validate_handover_bundle|resolved
- test:bats tests/maw_test.bats

Verification status: passed


## ws-issue10_t6_pr

Workspace: issue10_t6_pr

Summary: Phase1 proxy metrics script added and PR #18 opened; direct script smoke checks passed, but bats stalled in bats-preprocess in this shell.

Evidence refs:
- diff:34c75c9
- pr:#18
- test:scripts/phase1_metrics.sh | jq

Verification status: skipped

