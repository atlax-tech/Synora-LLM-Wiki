# P0-07 XPC/WASI feasibility

Status: `CHANGES_REQUIRED` for the full exit gate; the XPC bundle, policy boundary and checksum-verified Wasmtime bootstrap are present, while guest execution, capability callbacks, cancellation timing and crash/reconnect scenarios remain `NOT_RUN`.

The probe project embeds `SynoraAgentServiceProbe.xpc` only inside `SynoraP0Probes.app`. The service accepts a bounded request envelope, rejects expired or cancelled requests, and has no network or file entitlements. `SynoraSkillProbe` centralizes capability and loopback-domain checks. `CWasmtimeShim` is deliberately narrow: it checks a supplied dynamic library path without copying the Wasmtime C API into Swift.

The bootstrap script fixes Wasmtime `v48.0.1`, the official `aarch64-macos-c-api` asset URL and SHA-256, and extracts only under `.build/vendor/wasmtime`. It does not run an online installer or modify a shell profile.

Remaining work before P0 exit: link the verified C API into the service, exercise no-preopen filesystem and no-environment inheritance, brokered loopback, fuel/deadline, ≤100 ms cancel, active service abort and reconnect. The current `runtimeUnavailable` response is explicit evidence that execution is not yet accepted.
