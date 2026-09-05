# 原始产品基线档案

[2026-09-05-product-baseline.zip](2026-09-05-product-baseline.zip) 包含初始化前 9 份原始文档，字节不变；[source-hashes.json](source-hashes.json) 记录各原路径 SHA-256。ZIP 不包含原型代码、图片、依赖或构建产物。其内容是历史资料，旧编号、链接、路径和 QA 结论均不作为当前合同。

| 原文件 | 当前职责归属 |
|---|---|
| PRD.md | PRODUCT；八个验收场景移至 ACCEPTANCE；开放决策移至 unresolved |
| TECHNICAL.md | ARCHITECTURE；测试/性能移至 TESTING；技术门槛移至 ACCEPTANCE |
| DESIGN.md | DESIGN；按实际证据调整原生测量规则 |
| SPEC.md | SPEC；阶段退出门槛移至 ACCEPTANCE |
| PLAN.md | PLAN 任务；流程移至 DEVELOPMENT；测试移至 TESTING；验收移至 ACCEPTANCE |
| design-qa.md | design-qa 证据状态，不继承历史 passed |
| README.md | 根 README 清空；阅读入口为 AGENTS |
| prototype/AGENTS.md、prototype/README.md | 只对本地原型有效，不约束正式产品 |

必要时用 Python zipfile 或系统归档工具提取到临时目录阅读。禁止把归档展开回根目录，造成两套活动规范。
