# P0-07 XPC/WASI feasibility

Status: real guest execution, deadline, cancel and host-import isolation are verified; the capability callback broker and an active service abort/reconnect drill remain open.

The probe project embeds `SynoraAgentServiceProbe.xpc` only inside `SynoraP0Probes.app`. The service accepts a bounded request envelope, validates the Wasm header, deadline, module and response limits through `SynoraSkillProbe`, rejects expired or cancelled requests, and has no network or file entitlements. It accepts only same-user XPC connections and clears request lifecycle state after each response. The request deadline is forwarded to the runtime and the per-request cancel flag is polled by the epoch thread, so `cancel` bounds a running guest instead of only rejecting queued ones.

`CWasmtimeShim` is deliberately narrow: it accepts a canonical dynamic-library path only under the bootstrap root, creates the engine with `wasmtime_config_epoch_interruption_set`, and runs the guest under epoch interruption (`wasmtime_context_set_epoch_deadline`). No host imports, WASI preopens, environment variables or network capabilities are registered, so a guest cannot reach files, environment or network at all; an importing module fails instantiation. An epoch thread bumps the engine epoch when the deadline passes or the cancel flag is set, trapping the guest.

The bootstrap script fixes Wasmtime `v48.0.1`, the official `aarch64-macos-c-api` asset URL and SHA-256, and extracts only under `.build/vendor/wasmtime`. The script does not run an online installer or modify a shell profile.

Evidence (HEAD `b9f99e4`):

- `script/p0.sh skill` → exit 0, 8/8 tests with the verified library: a valid guest executes; an infinite-loop guest is trapped by a 200 ms deadline (observed ~255 ms including poll granularity); a cancel flag set at 50 ms ends the run in ~56 ms (≤100 ms budget); a module importing `env.f` fails instantiation; malformed modules and oversized response limits are rejected.
- `script/quality.sh` → exit 0 including the XPC end-to-end fixture: the gate builds the probe host, registers it under `~/Library/Caches/SynoraProbeHost`, launches it, and the host connects to its embedded XPC service which executes a real guest; the host persists `{"status":"success"}` in its container temp directory and the gate fails on any other status. Sandboxed app services are invisible to external processes, which is why the fixture runs inside the host.
- The full `script/quality.sh` run also builds the Release app and verifies bundle id, entitlements and codesign.

Remaining work before P0 exit: the capability callback path (guest requests a host-proxied capability through the broker) has no implementation yet, and no drill exists for an actively aborted service with reconnect. Both stay `NOT_RUN`; the isolation report does not claim them.
