# Synora Wiki 开发阶段规格

适用范围以 [PRODUCT §5.3](PRODUCT.md#53-当前服务与交付边界) 为准；DEFERRED 项不进入任何已规划阶段的依赖、完成率或退出门槛，不记为 BLOCKED，不要求 Apple 开发者账号。

文档版本：1.0
状态：CONFIRMED（规划基线）；P0 `CHANGES_REQUIRED`，P1–P9 `NOT_STARTED`。
解释：阶段只分配实现和验证时机，不删减产品能力。实现阶段交付可运行增量；探针阶段只需用最小代表性证据回答预定技术问题。不允许用不可用占位控件提前宣称功能完成。

## 1. 阶段原则

1. 先保护数据和编辑体验，再连接 AI 与范围内外部能力。
2. 每阶段只对本阶段交付负责；未完成的生产化矩阵由明确的后续阶段承接，不反向阻塞探针。
3. 数据迁移、日志脱敏、可访问性、性能和视觉回归在首次触及相关能力时开始，并在所属阶段和版本出口完整验证。
4. 高风险能力先做技术探针，再进入产品实现；探针验证方向而不代替生产实现。
5. 知识图谱分为“关系数据能力”和“可视化产品能力”。前者按知识引擎交付，后者等待独立高保真设计。

## 2. 阶段总览

| 阶段 | 名称 | 核心成果 | 主要依赖 |
|---|---|---|---|
| P0 | 架构与风险探针 | 技术决策、工程骨架、编辑/存储/Skill 可行性证据 | 无 |
| P1 | 原生壳层与设计系统 | 与高保真原型一致的可交互 Mac 主窗口 | P0 |
| P2 | 完整编辑与多媒体 | 可长期写作的块编辑器、媒体与版本恢复 | P1 |
| P3 | 本地数据、检索与开放库 | 可靠存储、全文搜索、导入导出、备份恢复 | P2 |
| P4 | AI Runtime、BYOK 与行内 AI | 多模型路由、审阅写入、Agent sidecar、行内建议 | P3 |
| P5 | LLM Wiki 引擎 | ingest/query/lint、规则演进、引用与关系数据 | P4 |
| P6 | Skills 与 MCP | 可安装、可授权、可隔离、可审计的扩展能力 | P5 |
| P7 | macOS 本地上下文与公开服务 | 照片、地图、CoreLocation + Open-Meteo、自有 Music Picker | P3–P6 |
| P8 | 回顾、知识体验与图谱设计门 | 完整手帐/知识流；完成图谱独立设计与技术验证 | P4–P7 |
| P9 | 系统级验证与个人发布 | 性能、安全、迁移、恢复、本地打包全部达标 | P1–P8 |

## 3. P0 — 架构与风险探针

当前状态与证据见 [P0 traceability](p0/traceability.md)。P0 只冻结方向和已知风险，不以后续阶段的生产级矩阵作为退出条件。

### 目标

把最可能导致返工的技术选择用可运行证据固定，而不是先写大量功能。

### 范围

- 建立 Xcode workspace、SwiftPM 模块、格式化、静态检查、测试与本地 CI。
- 完成 ADR：最低系统版本、TextKit 2 编辑模型、GRDB/SQLite、同步暂缓范围、XPC/WASI、Skill 包签名（不依赖 Apple 付费证书）。
- TextKit 2 探针：用中文/组合字符 range、一条 attachment 和 undo 路径验证编辑模型。真实 IME、VoiceOver、长文与媒体性能由 P2 收口。
- GRDB 探针：用小型确定性序列验证 WAL、operation log、重开和 replay 路线；大规模、磁盘满、反复中断和完整恢复由 P3/P9 收口。
- Skill 探针：执行真实 WASI guest，用代表性场景验证 XPC 崩溃隔离、超时/取消和一次未授权拒绝。完整 broker、资源限制和恶意矩阵由 P6 收口。
- 建立固定 seed 的可重复基准生成器，用 smoke profile 验证确定性，定义 10k records/100k blocks/20 GB media 的 full profile；完整数据物理生成与产品性能由 P3/P9 验收。
- 建立 threat model 和数据分类。

### 交付物

- 可构建的空壳工程与范围内必要 Package target（不含同步或 Companion）。
- ADR-001 至 ADR-006。
- 编辑/存储/Skill 探针报告及原始 benchmark。
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
- 自动保存、完整撤销/重做、版本历史、崩溃恢复和本地 revision 冲突保护。
- 手帐/笔记模板、元数据行、长文与媒体布局。
- 单条记录 Markdown/HTML/PDF/原始包导出。
- 在真实输入法、VoiceOver 和 100k 字/200 媒体场景下完成编辑产品级性能与稳定性收口。

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
- 在 10k records/100k blocks/20 GB media 完整数据上收口重放、索引、容量、磁盘满与中断恢复。

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
- 完成文件/网络 capability broker、资源限制、取消、崩溃和未提交写入回滚的生产级隔离矩阵。

### 交付物

- `SynoraSkillRuntime`、Skill 管理界面、权限中心。
- 三个示例 Skill：只读总结、来源翻译、可审阅的结构整理。
- Skill SDK/打包文档与安全清单。

### 退出门槛

见 [ACCEPTANCE.md](ACCEPTANCE.md) 对应阶段；不得越过未通过的门槛。

## 10. P7 — macOS 本地上下文与公开服务

### 目标

完成本机手帐上下文联动，无付费 Apple 服务或同步前置条件。

### 范围

- Photos、MapKit/CoreLocation、Share Extension、Services、App Intents、Spotlight 的免费可用本地能力及权限降级；不引入需付费会员的服务配置。
- CoreLocation 坐标 → Open-Meteo → 持久天气快照、attribution 与坐标外发控制。
- 自有 Music Picker 搜索与 Apple Music 分享链接转 MusicBlock，展示元数据并跳转外部音乐应用；不实现应用内播放或最近播放自动读取。
- 解析失败、网络关闭、权限撤销、导出恢复、撤销与迟到响应保护；技术契约见 ARCHITECTURE §14。
- P7-01…05、P7-11/12 DEFERRED；不创建同步/iPhone targets，不阻塞 P8/P9。

### 交付物

- `SynoraIntegrations`、原生音乐与天气卡片、免费可用的系统入口。
- Mac 真机集成、公开 API 契约、离线与权限矩阵报告。
- 隐私、来源标注、失败回退与恢复说明。

### 退出门槛

见 [ACCEPTANCE.md](ACCEPTANCE.md) P7；只计算在范围内任务。

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
- 数据迁移矩阵、备份恢复演练、本地故障注入和库修复工具。
- 安全评审、依赖审计、Skill/MCP 渗透场景、日志脱敏。
- App Sandbox、Hardened Runtime、免费本地签名/打包、开源构建说明；Developer ID、公证及 App Store 分发 DEFERRED。
- 用户手册、数据格式、Skill SDK、故障诊断与发布清单。

### 交付物

- 本机自用应用、可复现构建和源码包；不以外部分发信任或公证作为交付条件。
- 完整测试报告、已知限制、迁移/恢复手册。
- `v1.0.0` 数据格式与 API 兼容承诺。

### 退出门槛

见 [ACCEPTANCE.md](ACCEPTANCE.md) 对应阶段；不得越过未通过的门槛。

## 13. 跨阶段质量门

见 [ACCEPTANCE.md](ACCEPTANCE.md)；执行与追踪规则见 [DEVELOPMENT.md](DEVELOPMENT.md)。
