# 未决事项

以下项目均为 `UNRESOLVED`，只能在对应阶段用真实证据关闭。

| ID | 问题 | 影响与关闭条件 | 来源 |
|---|---|---|---|
| U-001 | 最低 macOS 版本与 Foundation Models 的设备、地区边界 | P0 ADR-001 与设备矩阵验证；macOS 15 仍为建议，不是部署承诺 | ARCHITECTURE、PLAN |
| U-002 | CKRecord、Asset 分片阈值、冲突和 tombstone 保留期 | P0 探针、P7 同步设计确定；不能假定 iCloud 已验证 | ARCHITECTURE、SPEC |
| U-003 | 中文 tokenizer、精确向量与 HNSW 切换阈值 | P3/P5 真实语料基准确定；50k chunks 为待测起点 | ARCHITECTURE |
| U-004 | Skill 签名信任根、私有源、撤销与 WASI 能力验证 | P0/P6 固化 ADR 与真实隔离证据；接口声明不等于安全通过 | ARCHITECTURE、PLAN |
| U-005 | 原生窗口、可访问配色、字体与三尺寸参考基线 | P1 按 DESIGN 校准并实测；旧 Web QA 不继承 | DESIGN、design-qa |
| U-006 | 知识图谱最终设计、渲染方案与帧率门槛 | P8 独立设计与性能验收；不得上线粗糙占位图谱 | SPEC、PLAN |
| U-007 | 原生构建测试命令、设备与签名账号、真实模型评测阈值 | 对应阶段建立真实工程、授权配置和预先确定的评测协议 | TESTING、PLAN |
| U-008 | 两次模型调用是否优于单次结构化提案（建议 09） | P5-05/13 按 TESTING 候选协议比较质量/费用/耗时；未验证，不冻结两次调用 | ADR-H002 |
| U-009 | RRF 与有限关系扩展的适用参数（建议 10） | P5-09/13 比较召回、引用、P95；权限过滤与证据预算不可放宽，不冻结权重/比例 | ADR-H002 |
| U-010 | Readability/Turndown 等网页解析器适配（建议 11） | P5-03/13 验证 DOM/原生运行边界、许可、解析质量和成本；不新增浏览器扩展产品、不冻结依赖 | ADR-H002 |

状态变更须同时记录证据路径与对应 ADR；缺少证据时保持未决。
