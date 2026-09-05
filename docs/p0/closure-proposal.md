# P0 受管文档同步提案

提案版本：`P0-CLOSURE-PROPOSAL-20260906-v2`

本提案是 Harness `harness-update` Phase A 的只读结果。输入绑定源码 HEAD `771d773aabeef344dedf4a569739d4ed5892c7c5`；任何下列输入哈希或源码 HEAD 变化都会使批准失效。

## 已确认事实

- `script/quality.sh` 在 `/private/tmp/synora-wiki-quality-a7c3fc4` 通过：11 个 Swift Testing tests、总行覆盖率 93.53%、正式应用 Debug/Release、probe host 与嵌入 XPC 集成构建、XCTest、XCUITest、签名和 entitlement 检查。提交态 `2736c64` 的隔离 clone 在 `/private/tmp/synora-wiki-quality-clean-2736c64` 通过同一门。
- `script/p0.sh all` 通过 probe build、store/skill focused tests、Wasmtime 48.0.1 下载校验与 deterministic smoke benchmark；P0-06 负向扫描无产品代码命中，README 仍为 0 字节，保护目录保持未跟踪。
- probe 集成日志确认 `SynoraAgentServiceProbe` 链接本地 `SynoraSkillProbe`，再嵌入 `SynoraP0Probes.app`。
- P0 仍是 `CHANGES_REQUIRED`：真实 TextKit IME/attachment/VoiceOver/延迟、100k store replay 与故障注入、真实 Wasmtime guest/capability callback/隔离矩阵、20 GiB full corpus、sentinel 扫描与远端 CI 均未完成。
- `validate_manifest.py` 通过。`detect_drift.py` 报告 5 项既有 drift：`.gitignore`、`AGENTS.md`、`ADR-H001`、初始化日志，以及 `ADR-H001` 的 source fingerprint。

## 输入哈希

| 文件 | SHA-256 |
| --- | --- |
| `AGENTS.md` | `1200e070068e80f5fdec188d22b5a0ea2b0314ef81d1ea24498b2e005ee817ed` |
| `docs/PLAN.md` | `814c0c87749f7050a1089f6363b61e55e04fecc07e614f6b4033ea7c43edf96b` |
| `docs/SPEC.md` | `4bb33fb3695b708d61d24ae1163909d3c4fa0454c9c03c6b5a96db21e1d82cda` |
| `docs/ACCEPTANCE.md` | `c86eff67d0cb6469788a25f4747eaa73a2a00118bf9576c79a0a362dc509cd14` |
| `docs/decisions/INDEX.md` | `7e4a78669bf3b1245eae70cd7e3590c53ef7de2118fb401038bd6c3d571bc6c5` |
| `.harness/manifest.json` | `83276af5effac7aee90a54359f4c555fedeaf72ce61a38ba29d714e9503e75a7` |
| `.harness/source-index.json` | `65302097ea335ad57c7cdce15b8a6135a9df2a150d759a512c136004fbfea828` |
| `.harness/unresolved.json` | `64105010cdccabe374c58e2763bd58f67b4db0e2eda34cc64b9b7f39f0b3ad6b` |

## 文件级同步计划

| 文件 | 拟议变更 | 分类 |
| --- | --- | --- |
| `AGENTS.md` | 将“P0–P9 均未启动”改为“P0 执行中，当前出口 CHANGES_REQUIRED；P1–P9 未启动”，不改边界规则 | `SAFE_MANAGED_UPDATE` |
| `docs/PLAN.md` | 在 P0 表前记录当前状态、源码 HEAD、已通过自动门与未完成出口；不改变 P0-01…10 的范围或依赖 | `SAFE_MANAGED_UPDATE` |
| `docs/SPEC.md` | 在 P0 节记录工程/探针已实现但完整风险矩阵未通过；不降低交付物 | `SAFE_MANAGED_UPDATE` |
| `docs/ACCEPTANCE.md` | 在 P0 验收处记录 `CHANGES_REQUIRED` 和未运行门；不把局部探针提升为 PASS | `SAFE_MANAGED_UPDATE` |
| `docs/decisions/INDEX.md` | 登记 ADR-001…006 为 `PROPOSED` 并链接现有文件 | `SAFE_MANAGED_UPDATE` |
| `docs/development-log/2026-09-06-p0.md` | 新建中文日志，记录实际 HEAD、命令、退出码、artifact、限制和人工验收步骤 | `SAFE_MANAGED_UPDATE` |
| `.harness/manifest.json` | 增加新日志，刷新上述获批受管文件哈希及 state 链接；保留 user/observed ownership | `SAFE_MANAGED_UPDATE` |
| `.harness/source-index.json` | 将 P0 实现、测试、ADR 和证据路径加入事实索引，状态保持 `CHANGES_REQUIRED` | `SAFE_MANAGED_UPDATE` |
| `.harness/unresolved.json` | 仅同步 U-001/U-004/U-007 的现有 P0 证据与剩余缺口，不改 unresolved 状态 | `SAFE_MANAGED_UPDATE` |

以下既有 drift 不在本提案中改正文或刷新 baseline：`.gitignore`、`docs/decisions/ADR-H001-initialization.md`、`docs/development-log/2026-09-05-initialization.md`。它们保持 `USER_EDIT_CONFLICT`，需独立核对来源后另行提案。`PRODUCT`、`DESIGN`、`ARCHITECTURE`、`TESTING`、`UNRESOLVED.md` 均为 `NO_CHANGE`。

## 验证与回滚

获批后先复核 HEAD 和全部输入哈希，再只改批准文件；运行 manifest、Harness structure、references、drift、`git diff --check` 和统一质量门。若验证失败，只恢复本次 Phase B 中字节仍未被并发修改的文件，并保留原始失败输出。现有 `USER_EDIT_CONFLICT` drift 会继续显式报告。

## 授权门

Phase B 需要用户明确批准 `P0-CLOSURE-PROPOSAL-20260906-v2` 及表中具体文件范围。批准只授权同步为“P0 执行中 / CHANGES_REQUIRED”，不授权关闭 P0、启动 P1、改变要求、推送或发布。
