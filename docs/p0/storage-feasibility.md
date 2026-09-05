# P0-05 GRDB/WAL feasibility

Status: `CHANGES_REQUIRED` for the full exit gate; the minimal transaction, revision and snapshot probe passes, while kill/reopen, corruption and disk-full fault injection remain `NOT_RUN`.

`Packages/SynoraCore` and the workspace lockfile pin GRDB `7.10.0`. `StoreProbe` uses `DatabasePool`, creates `records`, `blocks`, `assets`, append-only `operations`, `snapshots` and schema metadata, and requests SQLite WAL mode. A save validates the current revision, allocates a local sequence, appends a canonical operation hash, updates the projection in the same write transaction, and returns only after commit. Reused operation IDs are accepted only when their request fingerprint matches. The domain package contains no GRDB import.

Evidence:

- `swift test --package-path Packages/SynoraCore --enable-code-coverage` → all 11 package tests pass at source HEAD `771d773`; total core line coverage is 93.53%.
- The store regression test proves matching operation replay is idempotent, conflicting reuse is rejected, a stale revision leaves both the projection and operation count unchanged, and snapshot checksums round-trip. Snapshot selection skips a damaged newest row when an older valid row exists; full operation replay is not implemented.

Remaining work before P0 exit: exercise block/asset projection writes, implement and run 100k operation replay, add reordered-operation fixtures, and run process termination, damaged-snapshot fallback and constrained-disk `SQLITE_FULL` fault injection. These are not replaced by the current small probe.
