# Synora Wiki 开发任务计划

适用范围以 [PRODUCT §5.3](PRODUCT.md#53-当前服务与交付边界) 为准；DEFERRED 项不进入任何已规划阶段的依赖、完成率或退出门槛，不记为 BLOCKED，不要求 Apple 开发者账号。

状态：NOT_STARTED；方案细化不启动 P0–P9。

本文件只定义任务与依赖。阶段目标见 [SPEC.md](SPEC.md)，流程见 [DEVELOPMENT.md](DEVELOPMENT.md)，测试见 [TESTING.md](TESTING.md)，验收见 [ACCEPTANCE.md](ACCEPTANCE.md)。

## P0 — 架构与风险探针

### 任务拆分

| ID | 任务 | 依赖 | 输出 |
|---|---|---|---|
| P0-01 | 建立 Xcode workspace、targets、SwiftPM packages 和配置分层 | 无 | 可构建工程骨架 |
| P0-02 | 建立格式化、静态检查、单测、UI 测试与 CI | P0-01 | 质量门脚本与 CI 配置 |
| P0-03 | 定义 Domain entities、Repository/Clock/ID/Transaction 协议 | P0-01 | `SynoraDomain` v0 |
| P0-04 | TextKit 2 探针：IME、block ranges、attachment、undo、VoiceOver | P0-01 | 编辑器可行性报告 |
| P0-05 | GRDB WAL、operation log、snapshot/replay 探针 | P0-03 | 存储可行性报告 |
| P0-06 | DEFERRED：原 CKSyncEngine 同步探针，恢复需用户重新决策 | 无（移出依赖图） | 不开发、不验收、不阻塞 |
| P0-07 | XPC + WASI Skill 权限、崩溃、取消探针 | P0-01 | 隔离可行性报告 |
| P0-08 | 生成 10k records/100k blocks/20 GB media 基准库 | P0-03 | 固定 seed 测试数据 |
| P0-09 | 建立 threat model、数据分类和日志策略 | P0-03 | 安全文档 |
| P0-10 | 完成 ADR-001…006 并冻结主要技术路线 | P0-04/05/07/08/09 | 审批后的适用 ADR；原同步 ADR 仅记录暂缓决策 |

测试方法见 [TESTING.md](TESTING.md)，退出门槛见 [ACCEPTANCE.md](ACCEPTANCE.md)。

## P1 — 原生壳层与设计系统

### 任务拆分

| ID | 任务 | 依赖 | 输出 |
|---|---|---|---|
| P1-01 | 生成 color/type/spacing/radius/motion 语义 token | P0-10 | `SynoraDesignSystem` |
| P1-02 | 实现四栏 WindowGroup、列宽约束、折叠和恢复 | P1-01 | 主窗口壳 |
| P1-03 | 实现顶部工具栏、状态栏、菜单和命令 | P1-02 | 原生 chrome |
| P1-04 | 实现侧栏分区、选中/悬停/计数和工具区 | P1-02 | LibraryNavigation |
| P1-05 | 实现搜索、笔记/手帐 selector、时间分组列表 | P1-02 | RecordList |
| P1-06 | 实现上下文与 AI Skills 检查器容器 | P1-02 | Inspector shell |
| P1-07 | 完成 loading/empty/error/offline/conflict 状态组件 | P1-04…06 | State catalog |
| P1-08 | 键盘焦点、VoiceOver、减少动态和高对比度 | P1-03…07 | Accessibility pass |
| P1-09 | 建立高保真三尺寸 snapshot 与像素比较 | P1-01…08 | Visual regression suite |
| P1-10 | XCUITest 覆盖主导航、列折叠、列表和检查器 | P1-02…08 | Shell UI tests |

测试方法见 [TESTING.md](TESTING.md)，退出门槛见 [ACCEPTANCE.md](ACCEPTANCE.md)。

## P2 — 完整编辑与多媒体

### 任务拆分

| ID | 任务 | 依赖 | 输出 |
|---|---|---|---|
| P2-01 | 定义 block schema、树不变量与 order key | P0-03 | Editor schema v1 |
| P2-02 | TextStorageAdapter 与 `SynoraTextView` | P0-04, P2-01 | 连续编辑核心 |
| P2-03 | 段落/标题/列表/任务/引用/代码/分隔线 | P2-02 | 基础 blocks |
| P2-04 | 表格/折叠/callout 与嵌套规则 | P2-03 | 高级 blocks |
| P2-05 | Markdown 快捷输入、斜杠菜单、@、[[ | P2-03 | 输入命令 |
| P2-06 | 选区格式栏、查找替换、拼写与复制粘贴 | P2-02 | 编辑工具 |
| P2-07 | Attachment staging、hash、缩略图与缓存 | P0-05 | Asset pipeline |
| P2-08 | 图片/拼贴/画廊、视频、音频、PDF、文件、链接 | P2-07, P2-03 | Media blocks |
| P2-09 | 自动保存、undo/redo、crash recovery、history；交付编辑所需真实事务/操作日志，P3 延续扩展 | P0-05, P2-02 | 编辑持久性；不得使用仅探针或内存 mock 验收 |
| P2-10 | 手帐/笔记模板和元数据行 | P2-03, P1-05 | Journal editing |
| P2-11 | 单记录 Markdown/HTML/PDF/原始包往返 | P2-03…10 | Record exporter |
| P2-12 | 长文/媒体/IME/VoiceOver 性能与稳定性收敛 | 全部 | Editor quality gate |

测试方法见 [TESTING.md](TESTING.md)，退出门槛见 [ACCEPTANCE.md](ACCEPTANCE.md)。

## P3 — 本地数据、检索与开放库

### 任务拆分

| ID | 任务 | 依赖 | 输出 |
|---|---|---|---|
| P3-01 | 实现 schema v1、迁移 runner 与事务仓储 | P0-05 | SynoraStore |
| P3-02 | 实现 append-only Operation 与快照策略 | P3-01 | History engine |
| P3-03 | 实现 Job queue、lease、checkpoint、retry/cancel；事件合并、作业世代与按库提交协调 | P3-01 | Durable jobs |
| P3-04 | 内容寻址附件、去重、垃圾回收与容量诊断 | P2-07, P3-01 | Asset store |
| P3-05 | FTS5 schema、增量索引与结果高亮；原文保存后独立索引 | P3-01 | Local search |
| P3-06 | 中文 tokenizer 候选基准与选择 ADR | P3-05, P0-08 | Search ADR |
| P3-07 | 时间/类型/标签/来源/媒体组合筛选 | P3-05 | Filter engine |
| P3-08 | Synora 开放格式 materializer/parser | P3-01, P2-11 | Library format v1 |
| P3-09 | 全量/增量备份、校验、恢复和库健康工具 | P3-02, P3-04, P3-08 | Recovery tools |
| P3-10 | 删除/tombstone/保留期与回收站 | P3-01…04 | Deletion lifecycle |
| P3-11 | 10k/100k 数据集性能与故障注入 | 全部 | Storage/search report |

测试方法见 [TESTING.md](TESTING.md)，退出门槛见 [ACCEPTANCE.md](ACCEPTANCE.md)。

## P4 — AI Runtime、BYOK 与行内 AI

### 任务拆分

| ID | 任务 | 依赖 | 输出 |
|---|---|---|---|
| P4-01 | `LanguageModelProvider`、请求/事件/capability 与通用 Proposal/ChangeSet 契约 | P3-01/02 | AI core；Wiki 可扩展校验接口 |
| P4-02 | Keychain profile、设置、连接测试和密钥删除 | P4-01 | BYOK settings |
| P4-03 | Apple/system/local OpenAI-compatible adapter | P4-01 | Local adapters |
| P4-04 | OpenAI/Anthropic/Gemini adapters | P4-01 | Cloud adapters |
| P4-05 | model discovery、capability matrix 与 contract fixtures | P4-03/04 | Provider contracts |
| P4-06 | 事件驱动 task router、统一上下文/费用预算、隐私、健康状态和 fallback | P4-05 | Model routing |
| P4-07 | structured output decode；通用 revision/权限/风险校验及 ChangeSet 原子应用 | P4-01, P3-02 | Safe AI output；真实存储提交/撤销 |
| P4-08 | diff/审批/provenance/撤销 UI | P4-07 | Review UI |
| P4-09 | 行内 ghost text、排版建议、stream、debounce、Tab/Esc/cancel；取舍选项与拒绝冷却 | P2-02, P4-06 | Inline AI |
| P4-10 | XPC Agent lifecycle、任务计划和 capability broker | P0-07, P4-06 | Agent service |
| P4-11 | AI 作业恢复、限流、超时、重试和离线排队 | P3-03, P4-10 | Reliable AI jobs |
| P4-12 | prompt/model/eval 版本与回归 harness | P4-05…11 | AI eval system |

测试方法见 [TESTING.md](TESTING.md)，退出门槛见 [ACCEPTANCE.md](ACCEPTANCE.md)。

## P5 — LLM Wiki 引擎

### 任务拆分

| ID | 任务 | 依赖 | 输出 |
|---|---|---|---|
| P5-01 | 实现 Raw/User/Wiki/Rules 数据边界与权限不变量 | P3-01 | Wiki domain |
| P5-02 | purpose/schema/policy 版本管理；确定性 index/log 投影 | P5-01 | RuleSet v1 |
| P5-03 | parser/chunker 定位与结构保真契约、来源 provenance；U-010 解析器实验 | P3-03, P5-01 | Normalize pipeline |
| P5-04 | 实体/事实/主题/摘要结构 schema；事实/偏好确认状态与有效时间 | P5-02 | Extraction schemas |
| P5-05 | 候选页/关系召回与 Proposal 生成接口；U-008 调用拆分实验 | P5-04, P3-05, P4-01/06 | Proposal builder |
| P5-06 | 在通用 validator 上接入 Wiki citation/schema、版本缓存与产物完整性校验，复用 revision/权限检查 | P5-05, P4-07 | Wiki Proposal validator |
| P5-07 | Wiki 风险策略接入 P4 ChangeSet 原子应用与撤销链；提交前重验与迟到结果丢弃 | P4-07/08, P5-06 | Wiki safe apply |
| P5-08 | embedding store、精确检索与模型版本重建 | P3-03, P3-05, P4-06 | Semantic index |
| P5-09 | 知识页/原文双通路 query、预算内证据扩展与引用校验；U-009 排序实验 | P5-08, P5-06 | Query engine |
| P5-10 | typed relations 与图谱数据查询 API | P5-05, P5-07 | Relation layer |
| P5-11 | 确定性/语义 lint、来源失效传播、增量及周期检查、修复 Proposal 与 Inbox Review | P5-06…10 | Lint engine |
| P5-12 | schema migration dry-run/rollback/alias | P5-02, P5-07 | Rule migration |
| P5-13 | ingest/query/lint 固定语料、并发/删除/恢复场景；独立真实模型评测与实验裁决 | 全部 | Wiki eval |

测试方法见 [TESTING.md](TESTING.md)，退出门槛见 [ACCEPTANCE.md](ACCEPTANCE.md)。

## P6 — Skills 与 MCP

### 任务拆分

| ID | 任务 | 依赖 | 输出 |
|---|---|---|---|
| P6-01 | manifest/包格式/schema/compatibility 定义 | P4-10 | Skill spec v1 |
| P6-02 | staging 解包、hash/signature、原子安装 | P6-01 | Installer |
| P6-03 | 权限模型、grant store 与权限预览 UI | P6-01, P4-02 | Permission center |
| P6-04 | Prompt-only runtime 与工具白名单 | P6-03, P4-10 | Prompt skills |
| P6-05 | WASI runtime、资源限制和虚拟文件系统 | P0-07, P6-03 | Executable skills |
| P6-06 | 网络 broker、域名/方法/大小/超时策略 | P6-03/05 | Network capability |
| P6-07 | 启停、升级、降级、卸载与依赖冲突 | P6-02 | Lifecycle manager |
| P6-08 | 调用审计、诊断与撤销关联 | P6-04…07 | Skill audit |
| P6-09 | MCP client、授权和 tool schema translation | P4-10, P6-03 | MCP client |
| P6-10 | loopback MCP server、短期 token 与关闭开关 | P6-03, P5-09 | Local MCP server |
| P6-11 | 三个示例 Skill、SDK 和安全文档 | P6-04…10 | Reference skills |
| P6-12 | 恶意包/注入/越权/崩溃/资源耗尽测试 | 全部 | Security report |

测试方法见 [TESTING.md](TESTING.md)，退出门槛见 [ACCEPTANCE.md](ACCEPTANCE.md)。

## P7 — macOS 本地上下文与公开服务

### 任务拆分

| ID | 任务 | 依赖 | 输出 |
|---|---|---|---|
| P7-01 | DEFERRED：原 CloudKit schema，恢复需用户重新决策 | 无（移出依赖图） | 不开发、不验收、不阻塞 |
| P7-02 | DEFERRED：原 CKSyncEngine，恢复需用户重新决策 | 无（移出依赖图） | 不开发、不验收、不阻塞 |
| P7-03 | DEFERRED：跨设备复制，恢复需用户重新决策 | 无（移出依赖图） | 不开发、不验收、不阻塞 |
| P7-04 | DEFERRED：跨设备合并与 Conflict Review，恢复需用户重新决策 | 无（移出依赖图） | 不开发、不验收、不阻塞 |
| P7-05 | DEFERRED：同步诊断与账户切换，恢复需用户重新决策 | 无（移出依赖图） | 不开发、不验收、不阻塞 |
| P7-06 | Photos 授权、相关候选和原件导入 | P2-08 | Photos integration |
| P7-07 | MapKit 地点、精度控制和地图卡片 | P2-10 | Location integration |
| P7-08 | CoreLocation + Open-Meteo 天气快照、隐私与 attribution | P7-07 | Weather integration |
| P7-09 | 自有 Music Picker、iTunes Search/Lookup、分享链接转 MusicBlock、外部打开 | P2-10 | Music integration |
| P7-10 | Share Extension/Services/App Intents/Spotlight | P3-01/05 | System entry points |
| P7-11 | DEFERRED：iPhone 采集伴侣，恢复需用户重新决策 | 无（移出依赖图） | 不开发、不验收、不阻塞 |
| P7-12 | DEFERRED：iPhone 健康桥接，恢复需用户重新决策 | 无（移出依赖图） | 不开发、不验收、不阻塞 |
| P7-13 | Mac 音乐/天气/照片/地点/系统入口真实集成、离线与权限矩阵 | P7-06…10 | 本地集成验证；不含 DEFERRED 项 |

测试方法见 [TESTING.md](TESTING.md)，退出门槛见 [ACCEPTANCE.md](ACCEPTANCE.md)。

## P8 — 回顾、知识体验与图谱设计门

### 任务拆分

| ID | 任务 | 依赖 | 输出 |
|---|---|---|---|
| P8-01 | 首页/今日聚合与轻量回顾策略 | P5, P7 | Home/Today |
| P8-02 | Inbox Review：失败、低置信、冲突、提案 | P5-11, P4-08 | Review center |
| P8-03 | 手帐年/月/主题视图与媒体叙事 | P2, P7 | Journal experience |
| P8-04 | 主题/来源/相关内容页面和回链 | P5-09/10 | Knowledge browsing |
| P8-05 | 周期总结、随机回顾、待办提取与频率控制 | P4, P5 | Reflection system |
| P8-06 | 复用既有上下文卡片呈现相关记录、协作选项与结果保存 | P4, P8-04 | Assistant UX |
| P8-07 | 用户接受/拒绝反馈形成 Rule Proposal；画像查看/纠正/停用/删除与个性化失效 | P5-12, P8-02 | Rule feedback 与画像闭环 |
| P8-08 | 知识图谱需求、信息架构与视觉探索 | P5-10 | Graph design brief |
| P8-09 | 图谱高保真原型、动效与可访问性规格 | P8-08 | Graph design contract |
| P8-10 | ForceAtlas2/Barnes–Hut + Metal 技术探针 | P5-10 | Graph benchmark |
| P8-11 | 图谱设计/性能评审门 | P8-09/10 | Go/hold decision |
| P8-12 | 仅在 go 后实现并测试图谱产品 UI | P8-11=go | Knowledge graph |

测试方法见 [TESTING.md](TESTING.md)，退出门槛见 [ACCEPTANCE.md](ACCEPTANCE.md)。

## P9 — 系统级验证与个人发布

### 任务拆分

| ID | 任务 | 依赖 | 输出 |
|---|---|---|---|
| P9-01 | 建立 FR→SPEC→PLAN→Test traceability 全表 | P0–P8 | Coverage matrix |
| P9-02 | 全量回归、随机长期运行和 soak test | P0–P8 | Stability report |
| P9-03 | 启动/输入/内存/能耗/搜索优化 | P9-02 | Performance report |
| P9-04 | 所有历史 schema/规则/Skill 格式迁移矩阵 | P3–P8 | Migration report |
| P9-05 | 备份、空机恢复、灾难恢复演练 | P3, P7 | Recovery sign-off |
| P9-06 | Threat model 收口、依赖审计、权限与日志扫描 | P0, P4–P7 | Security sign-off |
| P9-07 | VoiceOver、键盘、对比度、减少动态和中英文本地化 | P1–P8 | Accessibility sign-off |
| P9-08 | App Sandbox/Hardened Runtime、本地无需付费会员的构建与打包 | P9-06 | Release app |
| P9-09 | 可复现开源构建、许可证、数据格式和 SDK 文档 | P9-08 | Source release |
| P9-10 | 执行当前范围八个端到端验收场景 | 全部 | Final acceptance |

测试方法见 [TESTING.md](TESTING.md)，退出门槛见 [ACCEPTANCE.md](ACCEPTANCE.md)。
