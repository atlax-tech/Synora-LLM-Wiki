# P0-05 GRDB/WAL feasibility

Status: `CHANGES_REQUIRED` for the full exit gate; the minimal transaction, revision and snapshot probe passes, while kill/reopen, corruption and disk-full fault injection remain `NOT_RUN`.

`Packages/SynoraCore` pins GRDB `7.10.0` in `Package.resolved`. `StoreProbe` uses `DatabasePool`, creates `records`, `blocks`-ready operation metadata, append-only `operations`, `snapshots` and schema metadata, and requests SQLite WAL mode. A save validates the current revision, allocates a local sequence, appends a canonical operation hash, updates the projection in the same write transaction, and returns only after commit. The domain package contains no GRDB import.

Evidence:

- `swift test --package-path Packages/SynoraCore --enable-code-coverage` → all 8 package tests pass.
- The store regression test proves a stale revision leaves both the projection and operation count unchanged, and validates snapshot checksum round-trip.

Remaining work before P0 exit: add blocks/asset projection rows, 100k operation replay, duplicate/reordered operation fixtures, process termination, damaged snapshot fallback and constrained-disk `SQLITE_FULL` runs. These are not replaced by the current small probe.
