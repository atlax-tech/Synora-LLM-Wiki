# P0 受管文档收口提案

提案版本：`P0-CLOSURE-PROPOSAL-20260906-v1`

质量证据绑定的源码 HEAD：`3a5b466`（P0-08 benchmark determinism fix）；之后的 `f203ac3`、`30592cb` 只更新本提案。本文件是 Harness `harness-update` 的只读提案，不是授权，也不把 P0 标为完成。

## 已确认事实

- P0-01 至 P0-05、P0-07、P0-08 已有独立小步提交；P0-06 只有负向检查，P0-09 threat model、P0-10 六份 ADR 草案与 traceability/feasibility 文档已提交。
- 本机 `script/quality.sh` 默认 workspace 路径在当前源码状态通过：SwiftPM 8 tests、覆盖率总行 92.22%、Xcode Debug/Release build、XCTest、XCUITest、ad-hoc 签名检查；编译缓存定向到 `/private/tmp`，产物目录为 `/private/tmp/synora-wiki-quality-p0-workspace`。
- `script/p0.sh benchmark` 的 smoke profile 两目录逐文件比较与 `--resume` SHA-256 比对通过；full 10k/100k/20 GiB profile 未运行。
- TextKit 2 IME/attachment/undo/VoiceOver/performance、SQLite 故障注入、真实 Wasm 隔离/取消/崩溃、完整 benchmark、sentinel 日志扫描和独立清洁 clone 检查仍未完成。

## 建议的受管文件变更（需另行明确批准）

| 文件 | 建议 | 状态 |
| --- | --- | --- |
| `AGENTS.md` | 将阶段事实从“P0–P9 未启动”改为“P0 执行中，出口 `CHANGES_REQUIRED`”，保留所有边界规则 | `MANUAL_DECISION` |
| `docs/PLAN.md` | 仅更新顶层/ P0 状态与实际提交证据，不改任务范围、依赖或 DEFERRED 语义 | `SAFE_MANAGED_UPDATE` |
| `docs/SPEC.md` | 仅更新 P0 状态和已知限制，保留交付物及退出门槛 | `SAFE_MANAGED_UPDATE` |
| `docs/ACCEPTANCE.md` | 记录 P0 当前 `CHANGES_REQUIRED` 与未运行门槛，不降低标准 | `SAFE_MANAGED_UPDATE` |
| `docs/development-log/2026-09-05-p0.md` | 按日志规范追加本轮真实命令、HEAD、提交、限制和人工步骤 | `SAFE_MANAGED_UPDATE` |
| `docs/decisions/INDEX.md` | 登记 ADR-001…006 草案状态及链接，不标 `ACCEPTED` | `SAFE_MANAGED_UPDATE` |
| `.harness/manifest.json`, `.harness/source-index.json`, `.harness/unresolved.json` | 在上述文件批准后刷新受管基线和未决证据 | `SAFE_MANAGED_UPDATE` |

不建议本次修改 PRODUCT、DESIGN、ARCHITECTURE 或 `UNRESOLVED.md` 的要求/选型正文；六份 ADR 草案已把未决项和证据边界单独记录。若用户要改变这些受管源文件，需另建提案并保留冲突。

## 需要的授权

请明确批准提案版本 `P0-CLOSURE-PROPOSAL-20260906-v1` 的上述文件范围，或只批准其中列出的具体文件。批准前不执行受管文件、Harness 指纹或开发日志写入。
