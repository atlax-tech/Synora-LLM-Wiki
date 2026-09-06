# P0 traceability

| Task | Implementation | Automated evidence | Manual / missing evidence |
| --- | --- | --- | --- |
| P0-01 | workspace/project, app, probe, package, configs, ad-hoc entitlements | workspace list, app Debug/Release builds, probe/XPC integration build | none specific to the skeleton |
| P0-02 | strict format, package tests, coverage artifact, quality script, CI | `script/quality.sh` exit 0 at HEAD `b9f99e4`: format lint, package tests + coverage, Debug/Release/probe builds, XCTest/XCUITest, entitlements, XPC fixture, sentinel scan, `git diff --check` | run the focused checks relevant to the final P0 code; remote/full release CI belongs to the version gate |
| P0-03 | `SynoraDomain` contracts, UUID/revision/hash types | domain tests | larger property sequences belong to the owning implementation stage |
| P0-04 | TextKit 2 bridge and Unicode fixture | probe build, XCUITest window launch | verify one representative attachment/undo path on the final P0 tree; real IME, VoiceOver and 100k-char performance move to P2 |
| P0-05 | records+blocks+assets projections, snapshot recovery, shared replay state machine | `script/p0.sh store` exit 0: seeded 100k mixed ops converge across replay/snapshot recovery, 3× SIGKILL reopen with complete hash chain, `SQLITE_FULL` on 6 MiB APFS image with recoverable last commit, sequence reorder rejected atomically | none storage-specific |
| P0-06 | no code or target added | negative scan rerun at HEAD `b9f99e4`: 0 product-code matches | rerun at final closure HEAD |
| P0-07 | epoch-interruption deadline + cancel in shim, service policy, capability host import and XPC fixture | `script/p0.sh skill` exit 0 (9/9: real guest, deadline, cancel, representative allow/deny and bounds); `script/quality.sh` XPC fixture plus SIGKILL crash/reconnect drill | rerun the focused Skill check on the final P0 tree; full file/network broker and malicious matrix move to P6 |
| P0-08 | deterministic smoke/full generator | full corpus at seed 20260905: exact 10k/100k/20 GiB, manifest hashes verified, TIFF opens via `sips`, tamper detected; smoke determinism + resume via `script/p0.sh benchmark` | none dataset-specific |
| P0-09 | threat model, classifications, sentinel scan | `script/quality.sh` sentinel scan clean over logs/xcresult/entitlements/release bundle (content sentinel planted in test data, secret sentinel reserved) | release-wide dependency/log review moves to P9 |
| P0-10 | ADR drafts and feasibility evidence | existing governance checks and prior review findings; ADR fixes applied at `93f47ad` | align applicable ADR status after the final focused P0 checks |

The table separates P0 feasibility evidence from later production acceptance. P0 closes after its final focused checks and applicable ADR/status alignment; P2/P3/P6/P9 retain the transferred product, scale, security and release requirements.
