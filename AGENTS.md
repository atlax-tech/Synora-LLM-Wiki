# Synora Wiki

个人、开源、原生 macOS 记录与知识库；完整产品范围见 PRODUCT。
当前只有规划与本地高保真参考，没有原生业务实现；P0–P9 均未启动。

## 必读与按需读取

每次先读本文件、[PLAN](docs/PLAN.md) 的目标阶段和最近 [开发日志](docs/development-log/)，再按改动范围读下表。首次接手读 PRODUCT 与 ARCHITECTURE；禁止每次全量加载档案。

| 权威文件 | 唯一职责／何时读取 |
|---|---|
| [PRODUCT](docs/PRODUCT.md) | 用户场景、FR 与完整范围；涉及行为/需求时 |
| [ARCHITECTURE](docs/ARCHITECTURE.md) | 目标选型、模型、依赖与数据边界；涉及技术时 |
| [DESIGN](docs/DESIGN.md) | 原生 UI/UX 约束；涉及界面时 |
| [SPEC](docs/SPEC.md) | 阶段目标、范围、交付物；阶段启动时 |
| [PLAN](docs/PLAN.md) | 任务 ID 与依赖；执行任务前 |
| [DEVELOPMENT](docs/DEVELOPMENT.md) | 开发流程、分支、追踪、Harness 命令；改动前 |
| [TESTING](docs/TESTING.md) | 测试方法与性能预算；制定和执行验证时 |
| [ACCEPTANCE](docs/ACCEPTANCE.md) | 阶段/产品退出门槛；判定完成时 |
| [design-qa](docs/design-qa.md) | 视觉验证事实与未验证状态；视觉验收时 |
| [决策索引](docs/decisions/INDEX.md) / [未决项](docs/decisions/UNRESOLVED.md) | 已决依据／唯一待决状态；冲突或信息缺口时 |
| [档案索引](docs/archive/INDEX.md) | 追溯原文；不得作为当前规范或全量默认上下文 |

最新用户指令优先；否则每份文档按职责裁决，时间戳不构成覆盖权。冲突/缺证据须指出并讨论，不自行取舍。跨文档用链接与 ID，勿重复抄写正文。

## 必须使用的 Skills

每次工程任务先调用已安装的 `ponytail:ponytail`（默认 full）并全程执行。先理解全链路，再依次复用现有实现、标准库、Apple 原生能力、已安装依赖，最后新增必要代码。

Ponytail 只减少无价值的实现复杂度，不能砍需求、降低验收、以 MVP/mock/占位替代真实交付，也不能省略安全、数据恢复、可访问性或明确要求的测试。与上述约束冲突的精简建议不适用。修复定位根因并查调用方；不做无关重构。只有用户明确停用才停用。

工程治理使用本机安装的 Harness Armor：初始化调用 `harness-build`，后续治理变更调用 `harness-update`，只读检查调用 `harness-check`。不得在 Harness-only 任务里编写业务代码。

## 边界与证据

- 从问题、约束和事实推理；不默认附和用户。结论区分 CONFIRMED、INFERRED、UNRESOLVED、CONFLICTED，并给来源；要求已确认不等于实现已通过。
- 先声明文件范围与验证方法，保护 user/observed 文件；发现未授权内容或不确定问题停止相关工作讨论。
- 只执行获准阶段；初始化不自动启动 P0，不创建空业务模块、Xcode 工程或产品 mock。
- 当前在 main 工作，发布后的分支规则见 DEVELOPMENT。不擅自发布、推送或保护分支。
- `local-reference/` 是 Git 忽略的本地原型与素材，不可 force-add 或上传；其嵌套 AGENTS 只约束原型目录。缺参考不能声称像素验收通过。
- 根 README 保持空白，直到用户另行授权。
- 任务完成需真实测试证据；执行、独立测试、独立评审不得合并为自证。仅检查文档不能宣称产品功能 PASS。
- `.agents/` 与 `.harness/` 仅是本机工具/状态目录，必须由 Git 忽略，不得 force-add 或作为仓库文档依赖。持久工程事实只写入 AGENTS 与 `docs/`。

治理检查命令见 [DEVELOPMENT](docs/DEVELOPMENT.md)；原生 build/test 尚不存在，不得声称验证。
