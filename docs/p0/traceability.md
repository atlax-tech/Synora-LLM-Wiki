# P0 traceability

| Task | Implementation | Automated evidence | Manual / missing evidence |
| --- | --- | --- | --- |
| P0-01 | workspace/project, app, probe, package, configs, ad-hoc entitlements | project list and Debug/Release builds | package targets are validated by SwiftPM separately; launch review pending |
| P0-02 | strict format, package tests, coverage artifact, quality script, CI | `script/quality.sh` and SwiftPM tests | SwiftPM branch coverage is unavailable in Xcode 26 output |
| P0-03 | `SynoraDomain` contracts, UUID/revision/hash types | domain tests | larger property sequence pending |
| P0-04 | TextKit 2 bridge and Unicode fixture | probe build | real IME, attachments, performance, VoiceOver pending |
| P0-05 | GRDB `DatabasePool` transaction/snapshot probe | store test | 100k replay, kill, corruption, disk-full pending |
| P0-06 | no code or target added | negative scan command | rerun at closure HEAD |
| P0-07 | XPC service, C shim, capability policy, bootstrap | service build and policy tests | live Wasm and isolation matrix pending |
| P0-08 | deterministic smoke/full generator | smoke test and script | full 20 GiB corpus and media opening pending |
| P0-09 | threat model and classifications | source review | sentinel log/artifact scan pending |
| P0-10 | ADR drafts and closure proposal | governance checks | independent clean-clone test/review and managed-doc approval pending |

The table intentionally records `NOT_RUN` work instead of promoting scaffolding to a phase pass.
