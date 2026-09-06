# 决策索引

| 决策 | 状态 | 依据 |
|---|---|---|
| [ADR-H001 工程初始化](ADR-H001-initialization.md) | ACCEPTED | 2026-09-05 用户当前会话指令 |
| [ADR-H002 Agent 与知识维护](ADR-H002-agent-knowledge.md) | ACCEPTED | 2026-09-05 用户批准 01–08 与体验建议；09–11 仅实验 |
| [ADR-H003 免费本地服务](ADR-H003-free-local-services.md) | ACCEPTED | 2026-09-05 用户明确调整付费 Apple 服务、同步、音乐与天气范围 |
| [ADR-001 平台基线](ADR-001-platform-baseline.md) | ACCEPTED FOR P0 / U-001 UNRESOLVED | macOS 26/arm64 开发基线冻结；设备/地区矩阵未完成 |
| [ADR-002 TextKit 2](ADR-002-textkit2-editor.md) | ACCEPTED FOR P0 / P2 VALIDATION | probe 构建与窗口路径有证据；真实编辑矩阵移交 P2 |
| [ADR-003 GRDB/SQLite](ADR-003-grdb-sqlite.md) | ACCEPTED FOR P0 / P3-P9 HARDENING | WAL/replay 探针证据；迁移与产品规模恢复移交后续阶段 |
| [ADR-004 同步暂缓](ADR-004-sync-deferred.md) | ACCEPTED / RECORD_ONLY | ADR-H003 范围决定与 closure HEAD 负向检查 |
| [ADR-005 XPC/WASI](ADR-005-xpc-wasi-isolation.md) | ACCEPTED FOR P0 / P6 HARDENING | focused isolation 10/10；信任、资源和恶意矩阵移交 P6 |
| [ADR-006 Skill 完整性](ADR-006-skill-package-integrity.md) | ACCEPTED FOR P0 DIRECTION / P6 UNRESOLVED | 完整性校验方向冻结；信任根与撤销仍为 U-004 |

技术待决项以 [UNRESOLVED.md](UNRESOLVED.md) 为唯一状态源。后续决策创建真实 ADR 后登记，不用索引代替技术证据。
