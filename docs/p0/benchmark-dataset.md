# P0-08 deterministic benchmark dataset

Status: full corpus generated and verified; media performance claims remain out of scope for P0 by design.

`SynoraBenchmarkGenerator` accepts `--profile smoke|full`, `--seed`, `--output` and `--resume`. The default seed is `20260905`. It writes JSONL records and blocks, a deterministic TIFF-capacity asset, and an atomic `manifest.json` containing schema, seed, counts, logical bytes, physical bytes and SHA-256 values. Resume reuses an existing manifest only when profile, seed, file presence and hashes agree.

Evidence (HEAD `b9f99e4`, corpus under Git-ignored `/private/tmp/synora-wiki-benchmark-full`):

- `swift run --scratch-path /private/tmp/synora-corpus-scratch SynoraBenchmarkGenerator --profile full --seed 20260905 --output /private/tmp/synora-wiki-benchmark-full` → exit 0. Manifest: `records: 10000`, `blocks: 100000`, `logicalAssetBytes: 21474836480` (exactly 20 GiB), `physicalBytes: 21484734260`, `schemaVersion: 1`.
- All three manifest SHA-256 entries recomputed and matched (`records.jsonl`, `blocks.jsonl`, `assets/payload.tiff`).
- `sips -g pixelWidth -g pixelHeight` opened the capacity TIFF through the system framework.
- A one-byte tampered copy of `records.jsonl` failed the manifest hash comparison, demonstrating tamper detection.
- The smoke profile keeps its earlier evidence: `script/p0.sh benchmark` generates twice, compares every file, and proves `--resume` is a no-op.

The full profile is intentionally opt-in because it allocates 20 GiB of local storage. It is never generated in Git or CI, and P0 does not claim media decode performance; that belongs to P2.
