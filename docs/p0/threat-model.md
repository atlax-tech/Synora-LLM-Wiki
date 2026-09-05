# P0-09 threat model and data classification

Status: `DRAFT FOR P0 REVIEW`. This document records controls implemented in the P0 probes and the evidence still required; it is not a claim that the product is secure or complete.

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
| malicious Wasm reads host files | guest filesystem | no service preopen; capability policy is explicit | `NOT_RUN` |
| path traversal or symlink escape | capability target | broker must canonicalize and allow only a temporary root | `NOT_RUN` |
| unauthorized network | host callback | only `127.0.0.1` allowlist is accepted by policy | unit test `PASS`; live request `NOT_RUN` |
| service crash or cancellation | XPC request | separate service bundle and structured failure envelope | build `PASS`; crash/reconnect `NOT_RUN` |
| stale or partial database write | SQLite transaction | revision check, operation append and projection share one transaction | regression test `PASS` |
| snapshot tampering | recovery | SHA-256 is stored and checked before use | unit test `PASS`; fallback `NOT_RUN` |
| dependency tampering | GRDB/Wasmtime | exact GRDB pin and Wasmtime SHA-256 | pin/bootstrap evidence |
| diagnostics leak content | logs/artifacts | current P0 code emits only status and hashes | sentinel scan `NOT_RUN` |

P0 exit requires replacing every `NOT_RUN` above with a repeatable artifact or keeping the phase open.
