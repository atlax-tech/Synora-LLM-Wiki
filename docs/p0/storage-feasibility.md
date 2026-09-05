# P0-05 GRDB/WAL feasibility

Status: automated scenarios complete; the remaining gaps are the human-only IME/VoiceOver gates that do not belong to storage.

`Packages/SynoraCore` and the workspace lockfile pin GRDB `7.10.0`. `StoreProbe` uses `DatabasePool`, creates `records`, `blocks`, `assets`, append-only `operations`, `snapshots` and schema metadata, and requests SQLite WAL mode. Every write validates the current revision, allocates a local sequence, appends one canonical hash-chained operation, updates the projection in the same write transaction, and returns only after commit. Reused operation IDs are accepted only when their request fingerprint matches. `block.save`, `block.delete` and `asset.import` share the single append path with `record.save`; asset ids are content-addressed and reject content changes. The domain package contains no GRDB import.

`snapshot()` covers records, blocks and assets. `recoverFromSnapshot()` restores the newest valid snapshot (falling back to a full replay when none exists) and replays only operations after `up_to_sequence`. `replayProjection()` rebuilds all three tables after validating the complete operation chain, and rejects reordered sequences, damaged hashes and kind-invariant violations without touching the projection.

Evidence (HEAD `8313181`):

- `script/p0.sh store` → exit 0 for `SynoraStoreProbeTests` (idempotency, conflict, stale revision, corrupt-log atomicity, block/asset round trip with sentinel content) and `SynoraStoreHeavyTests`:
  - `seeded100kMixedOperationsConvergeAcrossReplayAndSnapshotRecovery`: exactly 100,000 fixed-seed (20260905) mixed record/block/asset operations; projection hash equals full-replay hash equals snapshot-recovery hash. Runtime ~504 s (fsync per transaction).
  - `killedWriterLeavesOnlyCompleteTransactionsAfterReopen`: the crash-writer subprocess was SIGKILLed in three separate rounds at increasing transaction counts; each reopen replayed a complete hash chain with a stable projection hash and lost at most the trailing record+block pair.
  - `constrainedVolumeReportsDiskFullAndKeepsLastCommitRecoverable`: a 6 MiB APFS disk image triggered `SQLITE_FULL`; the last committed record stayed readable and replayed cleanly from a byte-identical copy moved off the full volume.
  - `replayRejectsSequenceReorderAtomically`: swapped sequence values throw `invalidOperation` and leave the projection unchanged.
- `script/quality.sh` → exit 0 at HEAD `b9f99e4` with the light store suite, coverage gate and app/probe builds.

The heavy suite runs through `script/p0.sh store` only; `script/quality.sh` skips it to keep the fast gate bounded.
