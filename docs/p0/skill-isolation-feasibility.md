# P0-07 XPC/WASI feasibility

Status: `ACCEPTED FOR P0 DIRECTION`; production Skill trust, resource and malicious-input validation is transferred to P6. The current focused isolation suite is green; the integrated quality gate's XPC phase was not reached because the probe UI application could not load accessibility.

The probe project embeds `SynoraAgentServiceProbe.xpc` only inside `SynoraP0Probes.app`. The service accepts a bounded request envelope, validates the Wasm header, deadline, module and response limits through `SynoraSkillProbe`, rejects expired or cancelled requests, and has no network or file entitlements. It accepts only same-user XPC connections and clears request lifecycle state after each response. The request deadline is forwarded to the runtime and the per-request cancel flag is polled by the epoch thread, so `cancel` bounds a running guest instead of only rejecting queued ones.

`CWasmtimeShim` is deliberately narrow: it accepts a canonical dynamic-library path only under the bootstrap root, creates the engine with `wasmtime_config_epoch_interruption_set`, and runs the guest under epoch interruption (`wasmtime_context_set_epoch_deadline`). No WASI preopens, environment variables or network capabilities are registered. The only host import a guest can see is `synora.request` (four i32 in, one i32 out) when the embedder registers a broker; every capability request reaches the embedder with the capability name and target read from guest memory, and everything unregistered fails instantiation. An epoch thread bumps the engine epoch when the deadline passes or the cancel flag is set, trapping the guest.

The bootstrap script fixes Wasmtime `v48.0.1`, the official `aarch64-macos-c-api` asset URL and SHA-256, and extracts only under `.build/vendor/wasmtime`. The script does not run an online installer or modify a shell profile.

Evidence at closure HEAD `ce4a71c`:

- `script/p0.sh skill` → exit `0`, 10/10 focused tests with the verified library: valid guest execution, deadline and cancel traps, malformed/bounds rejection, host-import isolation, path policy and broker allow/deny behavior.
- Earlier P0 quality evidence records the real guest XPC fixture and service crash/reconnect drill. The two current `script/quality.sh` attempts stopped at XCUITest before reaching that phase, so this closure does not pretend those steps were rerun.
- The same quality attempts reached successful Debug, Release and probe builds before the UI environment failure.

P6 owns the full file/network broker, resource limits, trust root, revocation, malicious matrix and product-runtime crash/rollback acceptance. The P0 direction does not authorize third-party Skill execution or claim a production security sign-off.
