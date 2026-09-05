# 决策索引

| 决策 | 状态 | 依据 |
|---|---|---|
| [ADR-H001 工程初始化](ADR-H001-initialization.md) | ACCEPTED | 2026-09-05 用户当前会话指令 |
| [ADR-H002 Agent 与知识维护](ADR-H002-agent-knowledge.md) | ACCEPTED | 2026-09-05 用户批准 01–08 与体验建议；09–11 仅实验 |
| [ADR-H003 免费本地服务](ADR-H003-free-local-services.md) | ACCEPTED | 2026-09-05 用户明确调整付费 Apple 服务、同步、音乐与天气范围 |
| [ADR-001 平台基线](ADR-001-platform-baseline.md) | PROPOSED / CHANGES_REQUIRED | P0 本机构建证据；设备矩阵未完成 |
| [ADR-002 TextKit 2](ADR-002-textkit2-editor.md) | PROPOSED / CHANGES_REQUIRED | probe 构建通过；真实编辑矩阵未完成 |
| [ADR-003 GRDB/SQLite](ADR-003-grdb-sqlite.md) | PROPOSED / CHANGES_REQUIRED | 事务单测通过；恢复故障注入未完成 |
| [ADR-004 同步暂缓](ADR-004-sync-deferred.md) | PROPOSED / RECORD_ONLY | ADR-H003 范围决定与 P0 负向检查 |
| [ADR-005 XPC/WASI](ADR-005-xpc-wasi-isolation.md) | PROPOSED / CHANGES_REQUIRED | XPC/policy 构建通过；真实 guest 隔离未完成 |
| [ADR-006 Skill 完整性](ADR-006-skill-package-integrity.md) | PROPOSED / UNRESOLVED | 仅依赖包校验；信任根仍为 U-004 |

技术待决项以 [UNRESOLVED.md](UNRESOLVED.md) 为唯一状态源。后续决策创建真实 ADR 后登记，不用索引代替技术证据。
