# 2026-09-05 工程治理初始化

状态：工程治理初始化；最终校验见下文。P0–P9 NOT_STARTED。

## 事实与来源

| 状态 | 事实 | 来源 |
|---|---|---|
| CONFIRMED | 完整个人产品，FR-SHELL/EDIT/MEDIA/WIKI/SEARCH/AI/SKILL/SYNC/PRIV 不删减 | 原始 PRD §1–18，封存档案；当前 PRODUCT |
| CONFIRMED | SwiftUI/TextKit 2/SQLite/CKSyncEngine/XPC/WASI 是目标方案，未实现 | 原始 TECHNICAL §2–19；当前 ARCHITECTURE |
| CONFIRMED | 当前会话授权初始化、归档、P4/P5 交换与 QA 校准 | ADR-H001 |
| CONFIRMED | 原生源码不存在；本地 React 原型只供参考 | 目录扫描及原型 README |
| CONFIRMED | remote main 原始提交 12f39a6b4c621e3dd16c0aa64c7d11aea07faf90 仅 LICENSE | git ls-tree / git log；origin/main |
| CONFIRMED | 九份原始文档字节保留 | archive ZIP 与 source-hashes.json |
| UNRESOLVED | 系统/设备/供应商可用性、原生视觉及 P0 技术风险 | decisions/UNRESOLVED.md；不是本轮实现结论 |

## 变更与工具来源

文件范围：根 AGENTS/README/.gitignore 与 docs 活动文件和封存档案；原型、图像、缓存、`.agents/` 与 `.harness/` 仅保留在本地忽略目录。未改原型业务代码，未创建正式产品代码。

采用 harness-build 文档构建流程。归档后原型已排除；扫描中 Python 是 Harness 工具，不是产品实现，因此语义状态为 DOCS_ONLY，而非按文件扩展名判为已开发。

Harness Armor v0.1.2 与 Ponytail 4.9.0 安装在本机项目工具目录供当前环境调用；该目录不属于产品仓库，也不作为干净克隆的文件依赖。

原始文档按档案索引分配唯一职责；阶段退出门槛集中到 ACCEPTANCE，方法集中到 TESTING。阶段调整的通用/专用校验分界见 ADR-H001，不新增需求。

## 验证结果

基于 origin/main `12f39a6` 的未提交初始化工作树；Python 3 标准库检查，macOS 本地环境：

- 调整前本机 Harness installer doctor 为 healthy=true；结构、引用和 drift 检查通过。随后按用户指令将 `.agents/`、`.harness/` 改为本地忽略目录；这些状态不再属于待提交产物。
- ZIP 9 条目逐文件 SHA-256 与原始清单一致；63 个 FR 表格行逐行一致；115 个任务 ID 按 P4/P5 映射完整保留且唯一；任务表无反向阶段依赖。
- 只复制 Git 文件到临时干净目录（无 local-reference）后，结构及 drift 检查均通过；本地资产不是治理检查的隐含依赖。
- main 跟踪 origin/main；LICENSE 未修改；README 为 0 字节；Git 忽略原型、图片和缓存，没有产品源码进入索引。
- `git diff --check` 对实际待提交文件通过；Git ignored 状态确认 `.agents/`、`.harness/` 与本地原型均被排除。

没有创建提交或推送；本轮是执行者收集的工程治理证据，不是独立产品测试/评审。旧 Web QA、原生 build/test、真实模型、设备同步均未运行。

## 人工复核

1. 查看根 AGENTS 阅读映射与 README 空白；git branch -vv 检查 main 上游。
2. 查看 SPEC 的 P4 AI / P5 Wiki；PLAN 无反向阶段依赖，原需求与任务仍在。
3. 按 archive/source-hashes.json 校验 ZIP 条目；Git 文件列表不包含 local-reference。
4. 按 DEVELOPMENT 检查 Git 空白与 ignored 状态；本机 Harness 输出不能替代产品测试。
