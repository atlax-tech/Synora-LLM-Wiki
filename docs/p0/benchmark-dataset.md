# P0-08 deterministic benchmark dataset

Status: `CHANGES_REQUIRED` for the full exit gate; the smoke profile is deterministic and resumable, while the 10k/100k/20 GiB profile and media-opening sample are `NOT_RUN`.

`SynoraBenchmarkGenerator` accepts `--profile smoke|full`, `--seed`, `--output` and `--resume`. The default seed is `20260905`. It writes JSONL records and blocks, a deterministic TIFF-capacity asset, and an atomic `manifest.json` containing schema, seed, counts, logical bytes, physical bytes and SHA-256 values. Resume reuses an existing manifest only when profile, seed, file presence and hashes agree.

Evidence:

- `swift test --package-path Packages/SynoraCore` → deterministic smoke generation and resume test pass.
- `script/p0.sh benchmark` generates the smoke profile in two clean directories, compares every file, then verifies `--resume` leaves the manifest unchanged.

The full profile intentionally remains opt-in because it allocates 20 GiB of local storage. It is never generated in Git or CI.
