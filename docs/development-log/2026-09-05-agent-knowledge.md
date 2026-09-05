# 2026-09-05 — Agent 与知识维护方案细化

## 范围

按用户批准更新 PRODUCT、ARCHITECTURE（兼技术规格）、SPEC、PLAN、TESTING、ACCEPTANCE 和决策索引/未决项；采纳映射见 [ADR-H002](../decisions/ADR-H002-agent-knowledge.md)。本轮仅文档，P0–P9 均未启动，无业务代码、依赖、提交或推送。

## 验证

基线 HEAD：`40fbda1f2d4019b8aa059e063d0c73f3d0c0064d`；macOS、本机 Python 3 标准库。

- 执行者：`git diff --check` 退出 0；本机 Harness manifest、结构及引用检查通过。机器检查不代表产品功能通过。
- 本机既有指纹与 Git 当前文档存在漂移；只刷新本轮编辑文件的基线，未改动文件的既有漂移保留，不回滚用户内容。
- 独立检查：`git diff --check` 退出 0；引用检查 51 条、0 断链；Python 比对 HEAD 确认 63 个 FR、115 个任务 ID 保留且唯一，无反向阶段依赖。DESIGN/README 相对 HEAD 未变，README 为 0 字节；本轮无原型写操作，未做原型全目录哈希比较。
- 独立语义评审：修复 PRODUCT 系统/模型维护职责冲突与未决表格断行后 PASS（仅文档）；01–08/09–11 边界及画像链路已复核。
- 原生 build/test、真实模型、成本、搜索性能、同步与视觉均未运行。

## 人工复核

1. 对照 ADR-H002 的批准项映射与 Git diff；确认 09–11 只在未决项中等待实验。
2. 检查 FR 与任务 ID 保留，P4 通用能力、P5 Wiki、P8 画像闭环无反向依赖。
3. 检查 DESIGN、README、原型与档案未改；需求/方案确认不等于实现验收。
