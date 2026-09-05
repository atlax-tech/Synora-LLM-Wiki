# Synora Wiki 测试规范

适用范围以 [PRODUCT §5.3](PRODUCT.md#53-当前服务与交付边界) 为准；DEFERRED 项不进入任何已规划阶段的依赖、完成率或退出门槛，不记为 BLOCKED，不要求 Apple 开发者账号。

状态：CONFIRMED（测试要求）；原生测试命令与结果 UNRESOLVED，未创建工程、未运行产品测试。

测试替身仅可用于单元/故障注入；不能替代真实实现、设备或供应商验收。

## 全局测试方法

| 方法 | 何时运行 | 主要产物 |
|---|---|---|
| Unit/Property | 每次提交 | XCTest/Swift Testing 报告、随机种子 |
| Integration | 每个 PR、每日主干 | 临时库、迁移、作业、索引、Keychain fake |
| Contract | Provider/公开音乐天气 API/MCP 变更 | 录制 fixture、schema diff、live opt-in 结果 |
| Snapshot | UI 变更 | 三尺寸基线、差异图、颜色/布局阈值 |
| XCUITest | 每个 Feature 合入 | 核心路径视频/日志、失败截图 |
| Performance | 每日主干、阶段出口 | 启动/输入/搜索/导入 trend |
| Recovery/Fault injection | 存储、AI、外部集成、Skill 变更 | kill/断网/磁盘满/重复事件报告 |
| Accessibility | 每阶段 | VoiceOver 脚本、键盘路径、对比度报告 |
| Security | P0 后持续，P6/P9 完整运行 | threat model、依赖/权限/日志扫描 |

## 测试分层与预算

### 测试层

| 层 | 内容 | 门槛 |
|---|---|---|
| Unit | domain、block operations、risk policy、routing、merge | 核心包行覆盖 ≥ 85%，分支 ≥ 75% |
| Property | operation replay、顺序键、幂等、导入导出往返 | 随机序列无不变量破坏 |
| Integration | SQLite/FTS/assets/jobs/Keychain fake | 每个迁移和失败点覆盖 |
| Contract | 各模型 adapter、structured output、stream/cancel/error | fixture+live opt-in 双套 |
| UI | 编辑、媒体、AI、搜索、冲突、Skills、设置 | 关键旅程全自动 |
| Snapshot | 1280×720、1440×900、1728×1117 | 符合 `DESIGN.md` 阈值 |
| Performance | 启动、输入、长文、搜索、导入 | 达到下方预算 |
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
- 在无付费会员/无 Team/无云容器配置下实测本地 build/test 与 GRDB 恢复；CloudKit 探针及其 fake 均 DEFERRED。
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
- 搜索 goldens 覆盖中文、英文、混排、错别字、短语和过滤组合；无模型时新保存原文可检索。

### P4 — AI Runtime、BYOK 与行内 AI

- Mock server 注入流截断、429、5xx、无效 JSON、错序事件、慢响应和取消。
- Contract suite 以相同任务验证各 adapter capability 与降级。
- 行内 AI 在输入压力、IME、选区变化和快速取消下测主线程延迟。
- Agent 请求越权工具、超调用数、超预算和过期 revision，均应拒绝提交。
- 连续编辑、选区变化、IME、拒绝冷却和迟到响应验证不抢焦点、不改原文；中英文长历史/大工具结果验证总 token 预算、回答预留和引用完整性。
- 记录每类任务调用数、缓存命中、token 用量及费用估计，对照未合并事件/未复用结果基线；质量不能因节省调用而降低。

### P5 — LLM Wiki 引擎

- 固定原始语料与规则版本，对结构输出、引用、页面和关系做 golden diff。
- 对同一来源重复/中断 ingest、同名不同来源、乱序完成、取消和失败释放提交顺序，验证幂等键、checkpoint、revision 与迟到结果丢弃。
- 删除/损坏缓存产物、升级 parser/prompt/model/rules 后验证局部失效；显式删除不复活。同一数据重建 index/log 无漏项、重复或虚假成功日志。
- 长文、表格、代码、扫描件验证定位与精确事实保留；部分解析失败不能标完整成功。
- 人工插入矛盾、断链、无引用和 schema 违规，验证离线结构 lint 与模型语义 lint 不误删；拒绝项在证据/规则不变时不重复提醒。
- 来源删除/恢复验证多来源页、humanOverride、历史与引用失效；query 覆盖未整理记录、过期摘要与证据不足，检索扩展全程遵守权限和预算。
- 全量删除派生层并重建，与基准哈希/语义指标比较。

### P6 — Skills 与 MCP

- 生成路径穿越、符号链接、超大包、篡改签名、依赖环和降级攻击 fixture。
- 尝试未授权读取、写入、联网、环境变量和进程启动。
- XPC/WASI crash、无限循环、内存超限和取消，验证主应用稳定与事务回滚。
- MCP server 尝试非 loopback、过期 token、重放和超大 payload。

### P7 — macOS 本地上下文与公开服务

- iTunes fixture + opt-in live 查询覆盖 `media=music&entity=song`、storefront、空结果、429/超时、取消；公开接口验证不等于原生交互通过。
- 真实 Apple Music 分享链接覆盖歌曲路径、专辑 `i` 参数、无歌曲 ID、地区不匹配、失效/短链；未能查证的匹配不自动替换歌曲。搜索选曲和粘贴均生成原生 MusicBlock，失败可手工补全。
- 音乐卡片覆盖封面缺失、离线重开、导出导入/备份恢复、undo/redo、补全时删除或编辑；真实 Mac 验证点击交接本机 Music 及网页/复制回退，不以自动发声作为成功标准。
- CoreLocation 覆盖授权、拒绝、撤销、超时、位置不可用与城市选择；确认坐标降精度在外发前发生，关闭联网后无后续请求或迟到写入。
- Open-Meteo fixture + opt-in live 覆盖 current/daily、WMO 码、单位、时区跨日、无日出日落、断网/限流；快照与 attribution 持久化，旧记录不被当前天气覆盖。
- 免费本地 Photos/地图/系统入口实测；不请求 MusicKit/WeatherKit 权限，不含 CloudKit 容器或 Developer Token。记录系统版本及实际配置。
- 音乐/天气卡片执行三尺寸、键盘、VoiceOver 和文本对比度验证；不得把图标存在视作外部打开成功。

### P8 — 回顾、知识体验与图谱设计门

- 真实日常数据完成 30 天使用模拟，评估干扰、重复建议和可解释性。
- 手帐长文、密集照片、无元数据和部分授权状态逐屏 snapshot。
- 从任意既有视图新建无需分类；完成记录、整理、相关内容、查询与建议撤销闭环。
- 画像用显式偏好、单次情绪、相反事实、过期偏好、来源撤回和用户纠正验证：推测不冒充事实；停用/删除后不参与个性化、不自动重建；本地重启与备份恢复保持该状态。
- 图谱在 1k/10k/100k 节点验证布局收敛、缩放、选择和后台取消；用户测试比较可读性。

### P9 — 系统级验证与个人发布

- 用接近真实数据规模做 7 天 soak；注入进程终止、断网、磁盘临界和 provider 故障。
- 在干净 Mac 环境从本地构建/运行到恢复完整演练；不要求 iPhone、跨设备或公证安装。
- 静态/动态扫描 Keychain、entitlements、网络域名、日志、Skill/MCP 边界和导出包。
- 对发布构建而非 Debug 构建重复性能、snapshot 和 UI 主路径。

## 候选实验协议

U-008～010 使用固定语料、规则和预先登记的质量/性能/成本门槛；同类模型调用实验固定模型与配置。比较引用正确性、事实保留、召回、P95、调用量及费用；结构不变量精确断言，生成内容不要求逐字相同。保存失败和未采用结果，真实模型关闭/跳过不算通过。模型数据或提示变更须绑定新版本重测。候选未过门不改变已确认架构，也不降低产品验收。

## 视觉测量协议

固定系统版本、字体、语言、测试内容、窗口 contentLayoutRect（pt）与 backing scale；保存未缩放 PNG 像素尺寸和截图范围。不得按文件名推定 viewport；不同缩放/区域截图不能直接算 SSIM。排除系统窗口阴影、动态内容和照片后，比较相同内容区域；数值阈值见 DESIGN。任何裁切、焦点丢失、内容不可达仍直接失败。原生基线必须在 P1 实测建立。

## AI 真实验收

P4 在授权测试库与已配置模型上完成真实流式响应、提案审阅、持久提交和撤销；P5 以同一真实 runtime 验收 ingest/query/lint 与引用。缺少适用的 Mac 设备、BYOK 供应商配置或模型能力时记录该项 BLOCKED/未验证（不包括付费 Apple 账号及 DEFERRED 能力），不得用 fixture 宣称通过。Provider capability 差异保留矩阵与实际限制，不声称每个 provider 都支持全部模态。
