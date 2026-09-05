# 未决事项

除明确记录的范围关闭项外，以下项目为 `UNRESOLVED`，只能在对应阶段用真实证据关闭。

| ID | 问题 | 影响与关闭条件 | 来源 |
|---|---|---|---|
| U-001 | 最低 macOS 版本与 Foundation Models 的设备、地区边界 | P0 ADR-001 与设备矩阵验证；macOS 15 仍为建议，不是部署承诺 | ARCHITECTURE、PLAN |
| U-002 | RESOLVED（范围关闭）：原 CloudKit 同步探针 | ADR-H003 将同步 DEFERRED，技术未验证且不再要求验证，不是 P0/P7 blocker；本地 tombstone/附件回收仍由 P3 确定 | [ADR-H003](ADR-H003-free-local-services.md) |
| U-003 | 中文 tokenizer、精确向量与 HNSW 切换阈值 | P3/P5 真实语料基准确定；50k chunks 为待测起点 | ARCHITECTURE |
| U-004 | Skill 签名信任根、私有源、撤销与 WASI 能力验证 | P0/P6 固化 ADR 与真实隔离证据；接口声明不等于安全通过 | ARCHITECTURE、PLAN |
| U-005 | 原生窗口、可访问配色、字体与三尺寸参考基线 | P1 按 DESIGN 校准并实测；旧 Web QA 不继承 | DESIGN、design-qa |
| U-006 | 知识图谱最终设计、渲染方案与帧率门槛 | P8 独立设计与性能验收；不得上线粗糙占位图谱 | SPEC、PLAN |
| U-007 | 原生构建测试命令、Mac 设备与免费本地签名配置、真实模型评测阈值 | 对应阶段建立真实工程、免费本地配置和预先确定的评测协议；付费 Apple 账号不在关闭条件中 | TESTING、PLAN |
| U-008 | 两次模型调用是否优于单次结构化提案（建议 09） | P5-05/13 按 TESTING 候选协议比较质量/费用/耗时；未验证，不冻结两次调用 | ADR-H002 |
| U-009 | RRF 与有限关系扩展的适用参数（建议 10） | P5-09/13 比较召回、引用、P95；权限过滤与证据预算不可放宽，不冻结权重/比例 | ADR-H002 |
| U-010 | Readability/Turndown 等网页解析器适配（建议 11） | P5-03/13 验证 DOM/原生运行边界、许可、解析质量和成本；不新增浏览器扩展产品、不冻结依赖 | ADR-H002 |
| U-011 | 音乐分享链接映射与本机 Music 交接 | P7-09/13 真实样本验证；不保证全部链接可解析或自动播放，失败按 ARCHITECTURE §14.1 回退，不阻塞 P0 | [ADR-H003](ADR-H003-free-local-services.md) |
| U-012 | Mac 定位、Open-Meteo 时区/缺值及免费本地权限配置 | P7-07/08/13 实测；失败按 ARCHITECTURE §14.2 降级，不改用 WeatherKit，不阻塞 P0 | [ADR-H003](ADR-H003-free-local-services.md) |

状态变更须同时记录证据路径与对应 ADR；缺少证据时保持未决。
