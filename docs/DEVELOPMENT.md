# Synora Wiki 开发规范

状态：CONFIRMED；只约束后续获准的开发。

## 执行规则

### 完成定义（Definition of Done）

一个任务只有同时满足以下条件才可标记完成：

- 实现与验收用例同时合入，不留下不可用占位入口。
- 错误、空状态、离线、取消、权限拒绝和恢复路径已处理。
- 影响数据格式时包含向前迁移、回滚说明和旧 fixture 测试。
- 影响 UI 时包含三尺寸 snapshot、键盘和 VoiceOver 检查。
- 影响 AI/同步/Skill 时包含超时、重试、幂等、审计和故障注入。
- 文档、ADR、权限说明和 traceability matrix 同步更新。
- 没有引入密钥、用户正文或敏感提示词日志。

### 开发准则

1. **本地提交先行**：用户操作先成为本地原子事务；索引、AI 和同步只能后置。
2. **主线程只做 UI**：解析、缩略图、索引、模型、同步和 Skill 全部有可取消后台边界。
3. **协议隔离**：Feature 不直接依赖 GRDB、CloudKit、供应商 SDK、WASI 或 Keychain。
4. **稳定标识**：Record/Block/Asset/Operation 在创建时即获得稳定 ID。
5. **写入统一**：用户、AI、导入、同步都通过 Command → ChangeSet → Transaction 路径。
6. **AI 不可信**：自由文本不能直接写库；结构输出须验证引用、revision、权限和风险。
7. **原始内容不可变**：修正、合并、删除都通过版本、tombstone 和显式操作表达。
8. **可重建派生层**：FTS、向量、摘要、OCR、关系和知识页有版本且能重建。
9. **视觉合同**：不得自行“优化”`DESIGN.md` 的列宽、色彩、圆角和信息层级。
10. **小批次集成**：工程建立后每个批次保持工程可构建、库可迁移、数据可恢复。

### 分支与评审

- 首版发布前直接在 `main` 开发并跟踪 `origin/main`。首版发布后再配置 main 保护并创建 dev；本轮不执行。未来任务分支使用 `codex/p<阶段>-<短任务>` 或 `feature/p<阶段>-<短任务>`。
- 每个变更批次（采用 PR 时同样适用） 只承担一个可验证目标；数据迁移与视觉重构不在同一 PR 混做。
- 变更记录（或 PR）必填：关联需求 ID、风险、测试证据、数据迁移、UI 截图、隐私/权限变化、回滚办法。
- 领域/存储/同步/AI 安全模块至少两类证据：自动测试 + 设计/架构人工审查。

## 需求追踪模板

每个阶段执行计划复制并维护以下字段：

| Requirement | Spec Phase | Plan Task | Test Case | Evidence | Status |
|---|---|---|---|---|---|
| `FR-…` | `P…` | `P…-…` | `TC-…` | 日志/截图/报告链接 | Planned/In Progress/Passed/Blocked |

状态只能依据证据更新。若发现需求缺口，先更新 PRODUCT；若改变架构，先写 ADR；若改变视觉，先更新 DESIGN 并重新做对照 QA。

## 阶段启动清单

每个阶段开始前必须确认：

- 上一阶段所有退出门槛已通过或有正式例外记录。
- 本阶段任务被拆成可独立验收的 PR，依赖和 owner 清晰。
- 基准数据、测试设备、供应商账户和 Apple entitlement 已准备。
- 不确定的产品行为已回到 PRODUCT/DESIGN 决策，而不是由开发临场猜测。
- 性能、安全、迁移和可访问性预算已进入具体测试任务。

## 阶段结束清单

- 运行并保存全部阶段测试证据。
- 在发布构建上完成主旅程和视觉回归。
- 完成数据迁移、备份/恢复和故障注入。
- 更新 traceability、ADR、已知限制与用户说明。
- 只在全部退出门槛通过后建立下一阶段基线。

## Harness 操作

开始前读 AGENTS 和任务权威文档并声明文件范围；结束前检查变更、运行对应检查、写开发日志。原始档案只供追溯，活动文档才是当前依据。

Harness Armor 通过本机已安装的 `harness-build`、`harness-update`、`harness-check` 调用；`.agents/` 与 `.harness/` 不进入版本控制，仓库规范不能依赖其中的脚本或状态。持久的决策、未决项和验证结果分别写入 `docs/decisions/`、`docs/decisions/UNRESOLVED.md` 与 `docs/development-log/`。

仓库通用治理检查：

```sh
git diff --check
git status --short --ignored
```

原生 build/test/lint 命令由 P0 在创建真实工程并成功运行后登记；现在不得杜撰 xcodebuild scheme 或测试已通过。新阶段需用户给出执行计划，不因本轮初始化自动启动。

本机 Harness 检查结果只能证明当前环境；可复现的结论必须落在受 Git 跟踪的文档和测试证据中。
