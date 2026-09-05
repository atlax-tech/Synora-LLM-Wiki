# P0-07 XPC/WASI feasibility

Status: `CHANGES_REQUIRED` for the full exit gate; the XPC bundle, policy boundary and checksum-verified Wasmtime bootstrap are present, while guest execution, capability callbacks, cancellation timing and crash/reconnect scenarios remain `NOT_RUN`.

The probe project embeds `SynoraAgentServiceProbe.xpc` only inside `SynoraP0Probes.app`. The service accepts a bounded request envelope, validates the Wasm header, deadline, module and response limits through `SynoraSkillProbe`, rejects expired or cancelled requests, and has no network or file entitlements. It accepts only same-user XPC connections and clears request lifecycle state after each response. `CWasmtimeShim` is deliberately narrow: it accepts a canonical dynamic-library path only under the bootstrap root without copying the Wasmtime C API into Swift.

The bootstrap script fixes Wasmtime `v48.0.1`, the official `aarch64-macos-c-api` asset URL and SHA-256, and extracts only under `.build/vendor/wasmtime`. The isolated P0 run downloaded the archive, verified its SHA-256, and extracted it under `/private/tmp`; this does not prove that the service executes a guest. The script does not run an online installer or modify a shell profile.

The unified quality gate builds `SynoraP0Probes`, its local `SynoraSkillProbe` package dependency and the embedded XPC service. Remaining work before P0 exit: execute a real guest with the verified C API, add the capability callback, and exercise no-preopen filesystem and no-environment inheritance, brokered loopback, fuel/deadline, ≤100 ms cancel, active service abort and reconnect. The current `runtimeUnavailable` response is explicit evidence that execution is not yet accepted.
