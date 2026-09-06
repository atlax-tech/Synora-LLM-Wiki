# P0 traceability

| Task | Implementation | Automated evidence | Manual / missing evidence |
| --- | --- | --- | --- |
| P0-01 | workspace/project, app, probe, package, configs, ad-hoc entitlements | workspace list, app Debug/Release builds, probe/XPC integration build | probe launch review pending |
| P0-02 | strict format, package tests, coverage artifact, quality script, CI | `script/quality.sh` exit 0 at HEAD `b9f99e4`: format lint, package tests + coverage, Debug/Release/probe builds, XCTest/XCUITest, entitlements, XPC fixture, sentinel scan, `git diff --check` | SwiftPM branch coverage is unavailable in Xcode 26 output; remote CI pending first push |
| P0-03 | `SynoraDomain` contracts, UUID/revision/hash types | domain tests | larger property sequence pending |
| P0-04 | TextKit 2 bridge and Unicode fixture | probe build, XCUITest window launch | real IME, attachments, 100k-char performance, VoiceOver pending (human) |
| P0-05 | records+blocks+assets projections, snapshot recovery, shared replay state machine | `script/p0.sh store` exit 0: seeded 100k mixed ops converge across replay/snapshot recovery, 3× SIGKILL reopen with complete hash chain, `SQLITE_FULL` on 6 MiB APFS image with recoverable last commit, sequence reorder rejected atomically | none storage-specific |
| P0-06 | no code or target added | negative scan rerun at HEAD `b9f99e4`: 0 product-code matches | rerun at final closure HEAD |
| P0-07 | epoch-interruption deadline + cancel in shim, service enforces both, capability broker host import, XPC end-to-end fixture | `script/p0.sh skill` exit 0 (9/9: real guest, 200 ms deadline traps infinite loop, cancel ≤100 ms, broker receives guest capability requests, host imports rejected, bounds enforced); `script/quality.sh` XPC fixture `{"status":"success"}` plus SIGKILL crash/reconnect drill | none automation-specific |
| P0-08 | deterministic smoke/full generator | full corpus at seed 20260905: exact 10k/100k/20 GiB, manifest hashes verified, TIFF opens via `sips`, tamper detected; smoke determinism + resume via `script/p0.sh benchmark` | none dataset-specific |
| P0-09 | threat model, classifications, sentinel scan | `script/quality.sh` sentinel scan clean over logs/xcresult/entitlements/release bundle (content sentinel planted in test data, secret sentinel reserved) | dependency license review is documentation-level |
| P0-10 | ADR drafts and closure proposal | governance checks; independent test (clean clone, 34/0 pass) and independent review passed; review's ADR fixes applied at `93f47ad` | managed-doc approval, real IME/VoiceOver gates and remote CI pending |

The table intentionally records `NOT_RUN` work instead of promoting scaffolding to a phase pass. The phase cannot close before the human IME/VoiceOver gates, the capability-callback decision, independent test/review and remote CI pass.
