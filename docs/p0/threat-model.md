# P0-09 threat model and data classification

Status: `P0 ENGINEERING CLOSURE`; this document records probe-level controls and explicit later-stage hand-offs. It is not a product security sign-off.

## Trust boundaries

1. The main app owns user-facing state and future transactions.
2. The P0 probe host is an engineering-only process and embeds the XPC service.
3. The XPC service receives a single request envelope and delegates capability decisions to a broker boundary.
4. A future Wasm guest is untrusted code. It receives no implicit file preopens, environment variables, database path or network entitlement.
5. SQLite and the asset directory are local persistence boundaries. Logs and test artifacts are diagnostic boundaries that must not contain content or secrets.

## Data classes

| Class | Examples | P0 rule |
| --- | --- | --- |
| `Secret` | keys, signing material, authorization tokens | never stored in rows, logs or exported artifacts |
| `PrivateContent` | records, source text, media, prompts | local only; no raw content in diagnostics |
| `DerivedPrivate` | hashes, snapshots, probe results | rebuildable but still private |
| `OperationalMetadata` | counts, timings, error codes | allowed only in redacted diagnostics |
| `PublicStatic` | licenses and fixed policy names | safe to ship without user data |

## Threats and controls

| Threat | Entry | Control in this batch | Evidence state |
| --- | --- | --- | --- |
| malicious Wasm reads host files | guest filesystem | no service preopen, environment or network; unlisted imports fail instantiation | focused Skill test `PASS`; full malicious matrix `P6` |
| path traversal or symlink escape | capability target | canonical host-path policy maps only the logical temporary root | focused policy test `PASS`; real capability execution `P6` |
| unauthorized network | host callback | policy accepts only explicitly allowed loopback targets | policy test `PASS`; live capability request `P6` |
| service crash or cancellation | XPC request | separate service bundle, deadline/cancel trap and structured failure envelope | focused Skill tests `PASS`; prior P0 fixture/drill recorded; product crash matrix `P6` |
| stale or partial database write | SQLite transaction | revision check, operation append and projection share one transaction | focused store tests `PASS`; product recovery matrix `P3/P9` |
| snapshot tampering | recovery | SHA-256 is stored and checked before use | focused tamper test `PASS`; product fallback matrix `P3/P9` |
| dependency tampering | GRDB/Wasmtime | exact GRDB pin and Wasmtime SHA-256 bootstrap | `PASS` for probe dependency pinning |
| diagnostics leak content | logs/artifacts | sentinel policy scans only redacted outputs and release artifacts | prior P0 sentinel evidence recorded; current quality retry stopped before this phase; release review `P9` |

P0 closes when these probe-level controls, their actual evidence state and the later-stage ownership are recorded. P2/P3/P6/P9 remain responsible for real editor, storage, Skill security and release acceptance; no probe is being presented as production functionality.
