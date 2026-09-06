# Synora Wiki

个人、开源、原生 macOS 记录与知识库；完整产品范围见 PRODUCT。
P0 正在执行，当前出口为 `CHANGES_REQUIRED`；P1–P9 未启动。已有原生工程与专用风险探针，不构成产品业务功能完成。

付费 Apple 服务与同步范围见 [PRODUCT §5.3](docs/PRODUCT.md#53-当前服务与交付边界) 和 [ADR-H003](docs/decisions/ADR-H003-free-local-services.md)：不作为 P0 或后续阶段 blocker；保留本地功能与恢复质量门。

## 必读与按需读取

工程任务先读本文件，再定位 [PLAN](docs/PLAN.md) 的目标阶段和最近相关 [开发日志](docs/development-log/)；按下表读取任务所需正文。首次接手产品工程读 PRODUCT 与 ARCHITECTURE；纯规则维护只读受影响合同。禁止默认全量加载档案。

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

每次工程任务先调用已安装的 `ponytail:ponytail`（默认 full）并全程执行。实现策略按该 Skill 执行。

Ponytail 约束实现复杂度，不改变用户批准的功能范围。在当前任务和阶段内优先复用现有能力、标准库和原生能力，只实现达成当前目标所需的最小方案。探针、mock 和 fixture 可用于方案验证与测试；不得用它们冒充最终功能交付。修复定位共享根因，不做无关重构。

工程治理使用本机安装的 Harness Armor：初始化调用 `harness-build`，后续治理变更调用 `harness-update`，只读检查调用 `harness-check`。不得在 Harness-only 任务里编写业务代码。

开发日志遵守 [编写规范](docs/development-log/README.md)。

## 边界与证据

- 事实、推测和未验证项必须说清；只在存在真实冲突或会影响决策时使用 CONFIRMED、INFERRED、UNRESOLVED、CONFLICTED 标签。
- 非平凡或高风险改动先说明文件范围和验证方法；简单文档或局部修复可直接处理。始终保护 user/observed 文件；冲突只暂停受影响部分。
- 只执行获准阶段；初始化不自动启动 P0，不创建空业务模块、Xcode 工程或产品 mock。
- 当前在 main 工作，发布后的分支规则见 DEVELOPMENT。不擅自发布、推送或保护分支。
- `local-reference/` 是 Git 忽略的本地原型与素材，不可 force-add 或上传；其嵌套 AGENTS 只约束原型目录。缺参考不能声称像素验收通过。
- 根 README 保持空白，直到用户另行授权。
- 任务使用与改动相称的可运行检查；未运行就明确说明。独立对抗审查只在完整版本/发布候选收口或用户明确要求时进行，不随普通任务、步骤或提交触发。
- `.agents/` 与 `.harness/` 仅是本机工具/状态目录，必须由 Git 忽略，不得 force-add 或作为仓库文档依赖。持久工程事实只写入 AGENTS 与 `docs/`。
- 代码遵守 clean code；Git 小步提交表示一个完整、可回退的改动对应一次提交，不附加独立角色或全量验证。阶段任务在阶段结束时统一推送 GitHub；其他推送须另有授权。

治理检查命令见 [DEVELOPMENT](docs/DEVELOPMENT.md)；P0 自动 build/test 证据见 [P0 日志](docs/development-log/2026-09-06-p0.md)，未运行场景不得声称验证。
