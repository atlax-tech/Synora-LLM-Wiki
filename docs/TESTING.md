# Synora Wiki 测试规范

状态：CONFIRMED（测试要求）；原生测试命令与结果 UNRESOLVED，未创建工程、未运行产品测试。

测试替身仅可用于单元/故障注入；不能替代真实实现、设备或供应商验收。

## 全局测试方法

| 方法 | 何时运行 | 主要产物 |
|---|---|---|
| Unit/Property | 每次提交 | XCTest/Swift Testing 报告、随机种子 |
| Integration | 每个 PR、每日主干 | 临时库、迁移、作业、索引、Keychain fake |
| Contract | Provider/CloudKit/MCP 变更 | 录制 fixture、schema diff、live opt-in 结果 |
| Snapshot | UI 变更 | 三尺寸基线、差异图、颜色/布局阈值 |
| XCUITest | 每个 Feature 合入 | 核心路径视频/日志、失败截图 |
| Performance | 每日主干、阶段出口 | 启动/输入/搜索/导入/同步 trend |
| Recovery/Fault injection | 存储、AI、同步、Skill 变更 | kill/断网/磁盘满/重复事件报告 |
| Accessibility | 每阶段 | VoiceOver 脚本、键盘路径、对比度报告 |
| Security | P0 后持续，P6/P9 完整运行 | threat model、依赖/权限/日志扫描 |

## 测试分层与预算

### 测试层

| 层 | 内容 | 门槛 |
|---|---|---|
| Unit | domain、block operations、risk policy、routing、merge | 核心包行覆盖 ≥ 85%，分支 ≥ 75% |
| Property | operation replay、顺序键、幂等、导入导出往返 | 随机序列无不变量破坏 |
| Integration | SQLite/FTS/assets/jobs/CloudKit fake/Keychain fake | 每个迁移和失败点覆盖 |
| Contract | 各模型 adapter、structured output、stream/cancel/error | fixture+live opt-in 双套 |
| UI | 编辑、媒体、AI、搜索、冲突、Skills、设置 | 关键旅程全自动 |
| Snapshot | 1280×720、1440×900、1728×1117 | 符合 `DESIGN.md` 阈值 |
| Performance | 启动、输入、长文、搜索、导入、同步 | 达到下方预算 |
| Recovery | kill -9、磁盘满、断网、重复事件、旧版本迁移 | 无已确认内容丢失 |
| Security | 权限、Keychain、路径、Skill/MCP、日志脱敏 | 高危 0，越权 0 |

### 性能预算

- 10k 记录/100k blocks/20 GB 附件时冷启动 P95 ≤ 1.5 秒。
- 普通打字 keystroke-to-paint P95 ≤ 16 ms，P99 ≤ 32 ms。
- 打开 100k 字/200 媒体记录首屏 P95 ≤ 250 ms；媒体渐进加载。
- FTS P95 ≤ 150 ms；混合搜索 P95 ≤ 350 ms。
- 行内 AI 发起不阻塞输入；健康网络下首增量目标 ≤ 1.5 秒，可取消响应 ≤ 100 ms。
- ingest 与 embedding 后台 CPU/内存遵守系统热状态，编辑时自动降并发。

## 阶段测试方法

### P0 — 架构与风险探针

- 使用中文/英文/emoji/组合字符/第三方输入法 fixture 验证 TextKit range。
- 对 operation 随机生成 100k 次 insert/move/update/delete，并重放比对最终哈希。
- 模拟 CloudKit 重复、乱序、延迟和部分失败；验证幂等与冲突保留。
- 让 Skill 进程崩溃、超时、请求未授权路径/域名；验证主应用与数据不受影响。

### P1 — 原生壳层与设计系统

- 高保真原型与原生截图同屏比较；自动测 SSIM、关键几何和语义色。
- 调整窗口到最小/推荐/全屏、重启和多显示器移动，验证恢复。
- 仅键盘遍历；VoiceOver 读取层级与状态；减少动态开启后检查动画。

### P2 — 完整编辑与多媒体

- 每种 block 做 create/edit/move/nest/copy/paste/export/import/undo/redo 参数化测试。
- 在 marked text 中进行换行、撤销、切换 block，确保不拆坏中文输入。
- 导入时注入磁盘满、重复文件、损坏媒体和进程终止。
- 100k 字+200 媒体连续输入、快速滚动和选择，记录 signpost。

### P3 — 本地数据、检索与开放库

- 每个 migration 从所有历史 fixture 升级并校验回滚/备份。
- operation property test：重复、乱序、并发和中断后最终状态一致。
- 备份中随机损坏文件，确保恢复前校验并报告具体问题。
- 搜索 goldens 覆盖中文、英文、混排、错别字、短语和过滤组合。

### P4 — AI Runtime、BYOK 与行内 AI

- Mock server 注入流截断、429、5xx、无效 JSON、错序事件、慢响应和取消。
- Contract suite 以相同任务验证各 adapter capability 与降级。
- 行内 AI 在输入压力、IME、选区变化和快速取消下测主线程延迟。
- Agent 请求越权工具、超调用数、超预算和过期 revision，均应拒绝提交。

### P5 — LLM Wiki 引擎

- 固定原始语料与规则版本，对结构输出、引用、页面和关系做 golden diff。
- 对同一来源重复/中断 ingest，验证幂等键与 checkpoint。
- 人工插入矛盾、断链、无引用和 schema 违规，验证 lint 不误删。
- 全量删除派生层并重建，与基准哈希/语义指标比较。

### P6 — Skills 与 MCP

- 生成路径穿越、符号链接、超大包、篡改签名、依赖环和降级攻击 fixture。
- 尝试未授权读取、写入、联网、环境变量和进程启动。
- XPC/WASI crash、无限循环、内存超限和取消，验证主应用稳定与事务回滚。
- MCP server 尝试非 loopback、过期 token、重放和超大 payload。

### P7 — Apple 生态与多设备同步

- Fake engine + 真机 CloudKit 两套；注入网络切换、推送丢失、服务器拒绝和配额错误。
- 两设备随机并发 block 操作并最终比较 operation 集与 projection 哈希。
- 针对每个 Apple 权限测试 full/limited/denied/revoked。
- Health fixture 验证只同步摘要，不含原始 sample ID/原始记录。

### P8 — 回顾、知识体验与图谱设计门

- 真实日常数据完成 30 天使用模拟，评估干扰、重复建议和可解释性。
- 手帐长文、密集照片、无元数据和部分授权状态逐屏 snapshot。
- 图谱在 1k/10k/100k 节点验证布局收敛、缩放、选择和后台取消；用户测试比较可读性。

### P9 — 系统级验证与个人发布

- 用接近真实数据规模做 7 天 soak；注入进程终止、断网、磁盘临界和 provider 故障。
- 在两台干净 Mac 与一台 iPhone 上从安装到恢复完整演练。
- 静态/动态扫描 Keychain、entitlements、网络域名、日志、Skill/MCP 边界和导出包。
- 对发布构建而非 Debug 构建重复性能、snapshot 和 UI 主路径。

## 视觉测量协议

固定系统版本、字体、语言、测试内容、窗口 contentLayoutRect（pt）与 backing scale；保存未缩放 PNG 像素尺寸和截图范围。不得按文件名推定 viewport；不同缩放/区域截图不能直接算 SSIM。排除系统窗口阴影、动态内容和照片后，比较相同内容区域；数值阈值见 DESIGN。任何裁切、焦点丢失、内容不可达仍直接失败。原生基线必须在 P1 实测建立。

## AI 真实验收

P4 在授权测试库与已配置模型上完成真实流式响应、提案审阅、持久提交和撤销；P5 以同一真实 runtime 验收 ingest/query/lint 与引用。没有设备、账号、模型或能力时记录 BLOCKED/未验证，不得用 fixture 宣称通过。Provider capability 差异保留矩阵与实际限制，不声称每个 provider 都支持全部模态。
