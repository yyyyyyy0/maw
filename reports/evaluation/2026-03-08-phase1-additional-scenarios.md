# Phase 1 Additional Scenarios (2026-03-08)

Synthetic evaluation evidence for backlog A-004. This report is not proxy metrics output.

| scenario | passed | key checks | notes |
| --- | --- | --- | --- |
| merge_conflict | yes | merge_exit_code=1, unmerged_entries_count=3 | maw merge fails on conflicting same-line edits and leaves unmerged entries in the root repository. |
| ttl_expiry_doctor_fix | yes | before=2, after=0, claims_after_fix=0 | Expired claims are detected, removed by maw doctor --fix, and followed by a clean doctor --json --exit-code-mode multi run. |
| takeover_format_matrix | yes | full.plan=0, evidence.json=1 | takeover succeeds for all formats on full bundles, while evidence-only bundles keep md working and fail json/prompt/plan because the JSON sidecar is absent. |

## merge_conflict

Summary: maw merge fails on conflicting same-line edits and leaves unmerged entries in the root repository.

Passed: true

Evidence refs:
- cmd:maw merge ws1
- git:git ls-files -u
- log:merge_conflict/merge.log

Checks:
```json
{"merge_exit_code":1,"unmerged_entries_count":3,"conflict_detected":true}
```


## ttl_expiry_doctor_fix

Summary: Expired claims are detected, removed by maw doctor --fix, and followed by a clean doctor --json --exit-code-mode multi run.

Passed: true

Evidence refs:
- cmd:maw claim src/auth.ts --workspace ws1 --ttl 0
- cmd:maw doctor --json --exit-code-mode multi
- cmd:maw doctor --fix
- log:ttl_expiry_doctor_fix/doctor_before_fix.json
- log:ttl_expiry_doctor_fix/doctor_fix.log

Checks:
```json
{"expired_detected":true,"claims_before_fix":1,"claims_after_fix":0,"doctor_before_fix_exit_code":2,"doctor_after_fix_exit_code":0}
```


## takeover_format_matrix

Summary: takeover succeeds for all formats on full bundles, while evidence-only bundles keep md working and fail json/prompt/plan because the JSON sidecar is absent.

Passed: true

Evidence refs:
- cmd:maw handover --workspace ws1 --scope full
- cmd:maw handover --workspace ws1 --scope evidence
- log:takeover_format_matrix/full-*.out
- log:takeover_format_matrix/evidence-*.err

Checks:
```json
{"full_bundle":{"md":0,"json":0,"prompt":0,"plan":0},"evidence_only_bundle":{"md":0,"json":1,"prompt":1,"plan":1}}
```

