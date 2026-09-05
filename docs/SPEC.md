# Synora Wiki 开发阶段规格

文档版本：1.0
状态：CONFIRMED（规划基线；P0–P9 全部 NOT_STARTED）
解释：阶段用于降低工程与验收风险，不用于删减产品能力。每个阶段都必须交付可运行、可迁移、可测试的纵向切片；不允许用不可用占位控件提前宣称功能完成。

## 1. 阶段原则

1. 先保护数据和编辑体验，再连接 AI、同步与外部能力。
2. 每阶段有明确入口条件、交付物和退出门槛；未过门槛不得堆叠下一阶段复杂度。
3. 数据迁移、日志脱敏、可访问性、性能和视觉回归从第一阶段持续执行。
4. 高风险能力先做技术探针，再进入产品实现；探针代码不直接进入生产路径。
5. 知识图谱分为“关系数据能力”和“可视化产品能力”。前者按知识引擎交付，后者等待独立高保真设计。

## 2. 阶段总览

| 阶段 | 名称 | 核心成果 | 主要依赖 |
|---|---|---|---|
| P0 | 架构与风险探针 | 技术决策、工程骨架、编辑/同步/Skill 可行性证据 | 无 |
| P1 | 原生壳层与设计系统 | 与高保真原型一致的可交互 Mac 主窗口 | P0 |
| P2 | 完整编辑与多媒体 | 可长期写作的块编辑器、媒体与版本恢复 | P1 |
| P3 | 本地数据、检索与开放库 | 可靠存储、全文搜索、导入导出、备份恢复 | P2 |
| P4 | AI Runtime、BYOK 与行内 AI | 多模型路由、审阅写入、Agent sidecar、行内建议 | P3 |
| P5 | LLM Wiki 引擎 | ingest/query/lint、规则演进、引用与关系数据 | P4 |
| P6 | Skills 与 MCP | 可安装、可授权、可隔离、可审计的扩展能力 | P5 |
| P7 | Apple 生态与多设备同步 | iCloud、照片、地图、天气、音乐、iPhone 健康桥 | P3–P6 |
| P8 | 回顾、知识体验与图谱设计门 | 完整手帐/知识流；完成图谱独立设计与技术验证 | P4–P7 |
| P9 | 系统级验证与个人发布 | 性能、安全、迁移、恢复、签名打包全部达标 | P1–P8 |

## 3. P0 — 架构与风险探针

### 目标

把最可能导致返工的技术选择用可运行证据固定，而不是先写大量功能。

### 范围

- 建立 Xcode workspace、SwiftPM 模块、格式化、静态检查、测试与本地 CI。
- 完成 ADR：最低系统版本、TextKit 2 编辑模型、GRDB/SQLite、CKSyncEngine、XPC/WASI、包签名。
- TextKit 2 探针：中文 IME、10 万字、块边界、图片 attachment、撤销、复制粘贴、VoiceOver。
- CloudKit 探针：custom zone、CKSyncEngine state、离线写、重复事件、两设备冲突、大附件。
- Skill 探针：XPC 崩溃隔离、WASI 权限、取消/超时与 capability broker。
- 建立 10k 记录、100k blocks、20 GB 媒体的可重复基准数据生成器。
- 建立 threat model 和数据分类。

### 交付物

- 可构建的空壳工程与所有 Package target。
- ADR-001 至 ADR-006。
- 三个隔离探针报告及原始 benchmark。
- CI 质量门和测试数据集说明。

### 退出门槛

见 [ACCEPTANCE.md](ACCEPTANCE.md) 对应阶段；不得越过未通过的门槛。

## 4. P1 — 原生壳层与设计系统

### 目标

将当前 React 高保真原型一比一迁移为原生 macOS 交互壳，建立后续所有界面的视觉合同。

### 范围

- 四栏主窗口、栏位折叠/拖动/恢复、工具栏、状态栏、菜单和快捷键。
- 侧栏、记录列表、搜索框、分段切换、空/加载/错误/离线/冲突状态。
- 上下文/AI Skills 检查器切换。
- 语义颜色、排版、间距、圆角、图标和动效 token。
- 键盘焦点、VoiceOver 标签、减少动态效果、增加对比度。
- 1280×720、1440×900、1728×1117 截图基线。

### 交付物

- 可启动的 SwiftUI macOS app。
- `SynoraDesignSystem` package 与组件预览目录。
- XCUITest 导航路径和 snapshot suite。
- 与 `DESIGN.md` 的视觉差异报告。

### 退出门槛

见 [ACCEPTANCE.md](ACCEPTANCE.md) 对应阶段；不得越过未通过的门槛。

## 5. P2 — 完整编辑与多媒体

### 目标

交付可取代现有笔记/手帐编辑器的稳定写作核心。

### 范围

- 稳定 Block ID 与 block tree；段落、标题、列表、任务、引用、代码、分隔线、表格、折叠、callout。
- TextKit 2 连续编辑面、Markdown 快捷输入、斜杠菜单、`@` 与 `[[`。
- 选择格式栏、拖放、复制粘贴、查找替换、拼写检查、IME。
- 图片、画廊/拼贴、视频、音频、PDF、文件、链接预览。
- 自动保存、完整撤销/重做、版本历史、崩溃恢复和冲突占位机制。
- 手帐/笔记模板、元数据行、长文与媒体布局。
- 单条记录 Markdown/HTML/PDF/原始包导出。

### 交付物

- `SynoraEditorKit`、`SynoraAssets` 与 editor schema v1。
- 导入/导出 round-trip fixtures。
- 长文、媒体、IME、撤销和可访问性测试集。

### 退出门槛

见 [ACCEPTANCE.md](ACCEPTANCE.md) 对应阶段；不得越过未通过的门槛。

## 6. P3 — 本地数据、检索与开放库

### 目标

建立可长期维护、可恢复、可迁移的本地事实层。

### 范围

- GRDB/SQLite schema、迁移、WAL、事务与 operation log。
- Record/Block/Asset/Source/RuleSet/ChangeSet/Job 的完整仓储。
- 内容寻址附件、缩略图、去重、校验和容量诊断。
- FTS5 索引、中文 tokenizer 评测、过滤器、结果高亮。
- Synora 开放库格式、全量/增量备份、导入导出和恢复工具。
- durable job queue、checkpoint、重试、取消、事件合并与提交协调；原文索引不等待 AI。
- Trash/tombstone、历史保留和数据完整性检查。

### 交付物

- `SynoraStore`、`SynoraSearch` 基础、`SynoraAssets` 生产实现。
- schema migrations v1、恢复 CLI/开发工具、基准数据。
- 备份/恢复演练记录和哈希核对报告。

### 退出门槛

见 [ACCEPTANCE.md](ACCEPTANCE.md) 对应阶段；不得越过未通过的门槛。

## 7. P4 — AI Runtime、BYOK 与行内 AI

### 目标

提供统一、多模型、可审计的 built-in AI，并把轻量整理与深度 Agent 分开。

### 范围

- `LanguageModelProvider`、capability matrix、stream、structured output、embedding、token estimate。
- Apple 系统/本地模型、OpenAI-compatible、OpenAI、Anthropic、Gemini adapters。
- Keychain BYOK、连接测试、模型发现、路由、预算和隐私策略。
- 事件驱动轻量/深度任务路由、统一上下文与费用预算、结果复用、离线排队与故障切换。
- 通用 Proposal/ChangeSet 契约、revision/权限/风险 validator、diff、审批、原子应用与撤销；基于 P3 真实存储交付。Wiki citation/schema 扩展在 P5 接入，不反向依赖 P5。
- 行内 ghost text、选区改写、排版建议、取舍选项、Tab/Esc、取消和 debounce；沿用设计，不抢焦点。
- XPC Agent sidecar：计划、检索、工具调用、暂停/恢复/取消。
- Prompt/model/eval 版本与回归数据集；至少一条真实 provider → 提案 → 审阅 → 提交 → 撤销链，不能以模拟响应验收。

### 交付物

- `SynoraAIRuntime` 和 `SynoraAgentService`。
- 供应商契约测试、mock server fixtures 和 opt-in live tests。
- AI 设置、上下文预览、成本预览、provenance/diff UI。

### 退出门槛

见 [ACCEPTANCE.md](ACCEPTANCE.md) 对应阶段；不得越过未通过的门槛。

## 8. P5 — LLM Wiki 引擎

### 目标

让知识库结构由模型维护，同时保持来源、规则和每次变更可解释。

### 范围

- Raw/User/Wiki/Rules 分层和 `purpose/schema/policy/index/log`。
- ingest pipeline：保真解析与分块定位、实体/事实/主题提取、候选召回、提案、版本/产物/引用验证与协调提交。
- query pipeline：知识页与原文双通路混合检索，预算内渐进读取证据，带块级引用回答。
- lint pipeline：确定性与语义检查分离，覆盖断链、重复、孤立、矛盾、无引用、过期、schema 违规和来源失效。
- 规则版本、迁移 dry-run、影响预览、回滚和 alias。
- 用户反馈形成规则建议；事实/偏好带来源、时间和确认状态，为 P8 画像闭环提供数据契约。
- embedding、关系索引和未来图谱的数据 API。

### 交付物

- `SynoraWikiEngine`、向量索引与 relation schema。
- 基于固定语料的 ingest/query/lint goldens；U-008～010 仅为实验候选，采用须满足 TESTING 协议，不提前锁定调用次数、算法或解析依赖。
- provenance viewer 与 Inbox Review 数据模型。

### 退出门槛

见 [ACCEPTANCE.md](ACCEPTANCE.md) 对应阶段；不得越过未通过的门槛。

## 9. P6 — Skills 与 MCP

### 目标

让用户能安装 AI 能力，同时不把插件复杂度和安全成本转嫁给日常记录。

### 范围

- `.synoraskill` package、manifest、SKILL.md、resources 与可选 WASM。
- 安装、签名/hash、依赖/兼容、权限预览、启停、升级、降级、卸载。
- Prompt-only runtime、WASI executable runtime、网络/文件 capability broker。
- 工具调用日志、task audit、资源/时间/调用上限。
- MCP client；本地 MCP server 只绑定 loopback 并使用短期 token。
- 恶意包、路径穿越、prompt injection、越权、崩溃和超时测试。

### 交付物

- `SynoraSkillRuntime`、Skill 管理界面、权限中心。
- 三个示例 Skill：只读总结、来源翻译、可审阅的结构整理。
- Skill SDK/打包文档与安全清单。

### 退出门槛

见 [ACCEPTANCE.md](ACCEPTANCE.md) 对应阶段；不得越过未通过的门槛。

## 10. P7 — Apple 生态与多设备同步

### 目标

完成 Apple 手记式上下文联动和可靠的多设备数据闭环。

### 范围

- CKSyncEngine private zone、实体映射、asset 分片、state、tombstone。
- 不相交 block 自动合并、重叠编辑冲突审阅、规则/知识页提案合并。
- Photos、MapKit、WeatherKit、MusicKit 集成及授权降级。
- Share Extension、Services、App Intents、Spotlight（遵守隐私开关）。
- iPhone 伴侣：快速采集、分享、健康摘要选择与同步。
- 新设备 bootstrap、按需媒体、同步诊断和账户切换。

### 交付物

- `SynoraSync`、`SynoraIntegrations`、iPhone companion targets。
- 双设备自动化/手工设备矩阵报告。
- 权限、隐私、同步和恢复文档。

### 退出门槛

见 [ACCEPTANCE.md](ACCEPTANCE.md) 对应阶段；不得越过未通过的门槛。

## 11. P8 — 回顾、知识体验与图谱设计门

### 目标

把底层能力组织成完整、克制、长期有价值的日常体验，并为知识图谱建立独立质量门。

### 范围

- 首页、今日、收件箱、周期回顾、随机回顾、旅行/生活/日常/灵感手帐视图。
- 相关笔记、相关照片、主题页、来源页、AI 问答与 Inbox Review。
- 自动结构维护的可解释摘要、轻量规则反馈与可纠正个人画像；在既有知识页/审阅入口完成，不新增画像界面。
- **知识图谱独立设计阶段**：信息密度、节点/边、聚类、筛选、搜索、路径、时间、缩放、选择、无障碍。
- 图谱技术探针：后台 ForceAtlas2/Barnes–Hut，Metal 渲染，10k/100k 节点性能。
- 仅当高保真设计、动效和性能同时过门，才实现并启用图谱产品 UI。

### 交付物

- 完整日常知识/手帐体验。
- 知识图谱 DESIGN 附录、交互原型、动效规格和专项验收。
- Graph renderer 技术报告；通过后交付正式视图，否则保持 feature flag 关闭。

### 退出门槛

见 [ACCEPTANCE.md](ACCEPTANCE.md) 对应阶段；不得越过未通过的门槛。

## 12. P9 — 系统级验证与个人发布

### 目标

完成可长期自用的可靠发行版，而不是只在开发数据上工作的演示。

### 范围

- 全量功能回归、性能优化、内存/能耗、无障碍和本地化。
- 数据迁移矩阵、备份恢复演练、同步故障注入和库修复工具。
- 安全评审、依赖审计、Skill/MCP 渗透场景、日志脱敏。
- App Sandbox、Hardened Runtime、签名、notarization、开源构建说明。
- 用户手册、数据格式、Skill SDK、故障诊断与发布清单。

### 交付物

- 签名/公证应用、可复现构建和源码发布包。
- 完整测试报告、已知限制、迁移/恢复手册。
- `v1.0.0` 数据格式与 API 兼容承诺。

### 退出门槛

见 [ACCEPTANCE.md](ACCEPTANCE.md) 对应阶段；不得越过未通过的门槛。

## 13. 跨阶段质量门

见 [ACCEPTANCE.md](ACCEPTANCE.md)；执行与追踪规则见 [DEVELOPMENT.md](DEVELOPMENT.md)。
