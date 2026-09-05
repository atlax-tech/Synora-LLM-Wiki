# ADR-H002 — Agent 与知识维护方案细化

状态：ACCEPTED（设计决策，非实现通过）。日期：2026-09-05。

## 决策与范围

用户批准建议 01–08 进入方案，09–11 仅列实验；同时采纳统一记录入口、事件驱动 AI、减少调用、双通路检索、克制协作和可纠正画像。保留现有 FR 与任务 ID，画像细化并入 FR-WIKI-08；原生技术栈、DESIGN 与阶段状态不变。ARCHITECTURE 同时承担技术规格，不另建重复技术文档。

| 批准项 | 规范位置 | PLAN 交付 |
|---|---|---|
| 01 确定性 index/log | ARCHITECTURE §9.1 | P5-02 |
| 02 版本缓存与产物完整性 | ARCHITECTURE §9.2 | P5-06 |
| 03 并发准备与协调提交 | ARCHITECTURE §9.2 | P3-03、P5-07 |
| 04 统一上下文预算 | ARCHITECTURE §11.2 | P4-06 |
| 05 结构/语义 lint | ARCHITECTURE §9.4 | P5-11 |
| 06 来源身份与删除影响 | ARCHITECTURE §9.4 | P5-11、P3-10 |
| 07 解析保真与检查点 | ARCHITECTURE §9.2 | P5-03 |
| 08 场景与真实模型评测 | TESTING P4/P5 | P4-12、P5-13 |
| 09–11 实验候选 | UNRESOLVED U-008～010 | P5-03/05/09/13 |
| 统一入口与协作 | PRODUCT §9、FR-AI-04/07 | P4-09/10、P8-06 |
| 成本与双通路检索 | ARCHITECTURE §9.3、§11.2 | P4-06、P5-09 |
| 可纠正画像 | PRODUCT FR-WIKI-08、§11；ARCHITECTURE §12.1 | P5-04、P8-07 |

方法与退出门槛分别由 [TESTING](../TESTING.md)、[ACCEPTANCE](../ACCEPTANCE.md) 唯一维护。实验状态仅在 [UNRESOLVED](UNRESOLVED.md) 更新；未通过时沿用既定契约，不减少功能。所有变更复用现有用例、队列、实体和审阅入口，不增加 Agent 框架或画像 UI。

## 依据与取舍

- [Karpathy LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)：持续知识层、不可变来源、规则及 ingest/query/lint 为底层模式；SQLite 事务源与开放 Markdown 镜像仍保留。
- [llm_wiki 固定审查版本 e808211](https://github.com/nashsu/llm_wiki/tree/e8082119649e6a8e1cf85eaf289adcabfdf39d4e)：参考 `src/lib/ingest.ts`、`ingest-cache.ts`、`ingest-commit-coordinator.ts`、`context-budget.ts`、`lint-structural-core.ts`、`source-lifecycle-delete.test.ts`、`ingest.scenarios.test.ts` 与 `src-tauri/src/commands/search.rs`。源码机制已观察，应用/测试/模型效果未实测；不照搬 FILE 写入、字符预算、级联删除或技术栈。
- [Mem Heads Up](https://help.mem.ai/features/heads-up)、[Cursor 行内协作](https://docs.cursor.com/en/get-started/quickstart)、[Graphiti](https://github.com/getzep/graphiti)：分别参考上下文推荐、接受/拒绝交互和时效事实；文档示例不是 Synora 收益证据，不引入整套依赖。

细化增加的是数据失效与触发规则，不是新的后台服务。主要代价是更完整的恢复与质量测试；成本收益保持待测。回退实验实现必须保留统一记录、引用、权限、恢复和撤销合同；后续规范变更另行评审。
