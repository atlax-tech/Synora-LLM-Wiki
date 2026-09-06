# P0-07 XPC/WASI feasibility

Status: real guest execution, deadline, cancel, host-import isolation, the capability callback broker and the crash/reconnect drill are verified; nothing in the isolation matrix remains `NOT_RUN` except human-side acceptance.

The probe project embeds `SynoraAgentServiceProbe.xpc` only inside `SynoraP0Probes.app`. The service accepts a bounded request envelope, validates the Wasm header, deadline, module and response limits through `SynoraSkillProbe`, rejects expired or cancelled requests, and has no network or file entitlements. It accepts only same-user XPC connections and clears request lifecycle state after each response. The request deadline is forwarded to the runtime and the per-request cancel flag is polled by the epoch thread, so `cancel` bounds a running guest instead of only rejecting queued ones.

`CWasmtimeShim` is deliberately narrow: it accepts a canonical dynamic-library path only under the bootstrap root, creates the engine with `wasmtime_config_epoch_interruption_set`, and runs the guest under epoch interruption (`wasmtime_context_set_epoch_deadline`). No WASI preopens, environment variables or network capabilities are registered. The only host import a guest can see is `synora.request` (four i32 in, one i32 out) when the embedder registers a broker; every capability request reaches the embedder with the capability name and target read from guest memory, and everything unregistered fails instantiation. An epoch thread bumps the engine epoch when the deadline passes or the cancel flag is set, trapping the guest.

The bootstrap script fixes Wasmtime `v48.0.1`, the official `aarch64-macos-c-api` asset URL and SHA-256, and extracts only under `.build/vendor/wasmtime`. The script does not run an online installer or modify a shell profile.

Evidence (HEAD `b9f99e4`):

- `script/p0.sh skill` → exit 0, 8/8 tests with the verified library: a valid guest executes; an infinite-loop guest is trapped by a 200 ms deadline (observed ~255 ms including poll granularity); a cancel flag set at 50 ms ends the run in ~56 ms (≤100 ms budget); a module importing `env.f` fails instantiation; malformed modules and oversized response limits are rejected.
- `script/p0.sh skill` also exercises the broker: a guest calling `synora.request("readTemporaryDirectory", "/tmp")` reaches the embedder broker with the exact strings from guest memory, an always-deny broker lets the run complete with the denial return code, and the XPC service denies any capability or loopback target outside the request policy (`App/SynoraAgentServiceProbe.swift`).
- `script/quality.sh` → exit 0 including the XPC end-to-end fixture and the crash/reconnect drill: the gate builds the probe host, registers it under `~/Library/Caches/SynoraProbeHost`, launches it, and the host connects to its embedded XPC service which executes a real guest; the host persists `{"status":"success"}` in its container temp directory. The drill then SIGKILLs the service, verifies the host stays alive, relaunches the host and requires a second `{"status":"success"}` from the respawned service. Sandboxed app services are invisible to external processes, which is why the fixture runs inside the host.
- The full `script/quality.sh` run also builds the Release app and verifies bundle id, entitlements and codesign.

Remaining work before P0 exit: only human-side acceptance (real IME/VoiceOver/performance) and remote CI; the isolation matrix itself has no open automated item.
