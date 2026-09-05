# 2026-09-05 — 免费本地服务与范围调整

## 范围与授权

用户明确授权修改相关文档，排除付费 Apple 服务和同步，音乐改自有 Picker/分享链接卡片，天气改 CoreLocation + Open-Meteo。按用户当前指令直接应用，不再次索要账号或范围确认。文件范围及替代关系见 [ADR-H003](../decisions/ADR-H003-free-local-services.md)。

仅文档与本机 Harness 状态更新，无业务代码、Xcode 工程、依赖安装、提交或推送；P0–P9 仍未启动。README 保持空白，历史日志与档案 ZIP 不重写，原型未执行写操作。

## 证据与验证

基线 HEAD：`1211af78290df0ec4916797a2cabada26298f4d3`；环境：macOS，Python 3 标准库。本轮运行公开文档查询，未调用用户位置或音乐账号。

- CONFIRMED：用户范围决定、公开 API 参数与条款见 ADR-H003；不是产品运行证据。
- 执行者：`git diff --check` 退出 0；本机 Harness manifest、structure、references 检查均退出 0，66 条引用、0 断链、无截断。
- 独立测试：初检确认 63 个 FR、115 个 PLAN ID 与 HEAD 一致且唯一，活动显式依赖不指向 DEFERRED 项；发现两处历史范围措辞和健康开关残留，已修正。最终复查 PASS（仅文档）：`git diff --check`、manifest/structure/references 均退出 0，66 条引用无断链；ID 和活动依赖复检通过。README 0 字节，档案 ZIP/原始哈希无 tracked diff。原型无事前全目录哈希，不能声称逐字节对照通过。
- 独立评审：主要文档语义 PASS，仅限文档；免费能力、音乐两入口、天气快照及恢复要求一致。新增来源、决策、档案替代说明及残留修正经独立复核 PASS，无新增矛盾。
- 本机 manifest 初检有效；既有 `.gitignore`、AGENTS、DEVELOPMENT、ADR-H001、初始化日志有旧基线漂移。本轮保留实际内容，只刷新已编辑文件，不掩盖未修改文件的历史漂移。最终 drift 检查退出 1，仅剩 `.gitignore`、ADR-H001 和初始化日志的既有漂移（ADR-H001 同时列为 source 漂移），均非本轮修改；没有本轮文档残余漂移。
- NOT_RUN：原生 build/test、真实音乐/天气 API 调用、CoreLocation、Music 交接、签名配置、视觉和可访问性验收。没有原生工程，不能声称产品 PASS。

## 人工复核与回滚

1. 对照 PRODUCT §5.3 和 PLAN：P0-06/P7-01…05/P7-11/12 为 DEFERRED，P0-10/P8-02 不依赖它们；P9 仅要求本机自用交付。
2. 对照 ARCHITECTURE §14、DESIGN §9.1 与 P7 测试/验收：搜索和粘贴两入口生成卡片，天气存快照，离线、权限拒绝与服务失败不阻塞保存。
3. 保留本地恢复、AI 冲突与安全质量门；无付费账号请求、同步 UI 或自动健康入口。
4. 如撤回本轮，只按本轮 diff 逆向恢复命名文档及对应本机状态；不要用旧档案覆盖后续用户改动。实际产品实现与链接覆盖率留在对应阶段实测。
