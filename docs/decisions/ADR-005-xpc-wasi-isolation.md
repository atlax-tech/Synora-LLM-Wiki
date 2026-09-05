# ADR-005 XPC 与 WASI Skill 隔离

状态：`PROPOSED / CHANGES_REQUIRED`；日期：2026-09-06；对应：P0-07、P0-10、U-004。

## 候选决策

可执行 Skill 通过独立 XPC service 承担生命周期边界，并在 WASI runtime 中运行；能力通过显式 broker policy 授权。默认不继承环境变量、文件 preopen 或网络；网络策略只允许明确声明的 loopback host。主应用是唯一可提交 ChangeSet 的边界。

## 证据

- `App/SynoraAgentServiceProbe.swift` 是独立 XPC target，只接受同用户连接，通过共享 policy 拒绝非法、过期、超限和已取消请求并返回结构化状态；request deadline 与取消标志透传到运行时。
- `CWasmtimeShim` 以 `wasmtime_config_epoch_interruption_set` + `wasmtime_context_set_epoch_deadline` 实现运行期中断：deadline 到期或取消标志置位时 epoch 线程递增 epoch，guest 被 trap 而非永久挂起。选择 epoch interruption 而非 fuel：deadline/取消语义直接映射 epoch 递增，无需按指令计费配置。
- `script/p0.sh skill`（HEAD `b9f99e4`，8/8 通过，使用 SHA-256 校验过的 Wasmtime 48.0.1 库）：合法 guest 正常执行；200 ms deadline 终止无限循环 guest（实测 ~255 ms）；50 ms 置位的取消在 ~56 ms 生效（≤100 ms 预算）；导入 `env.f` 的模块实例化失败——无 host import、无 WASI preopen、无环境继承、无网络，文件/环境/网络越权在结构上不可达。
- `script/quality.sh` 的 XPC 端到端 fixture：宿主 app 连接内嵌 XPC service 执行真实 guest，容器 temp 报告 `{"status":"success"}`，非 success 令质量门失败。
- 仍未运行：capability callback broker（guest 经 host 代理请求能力）、服务主动 abort 后的崩溃重连演练、远端 CI。

## 备选与后果

进程内执行更简单但会把 guest 崩溃和资源风险带入主应用；任意 shell 会突破能力合同。XPC/WASI 增加打包和 broker 工作，但保留主应用事务边界和可审计拒绝路径。

## 回滚点与未关闭项

若真实隔离矩阵失败，保留请求/结果合同和策略测试，暂停可执行 Skill 交付，不退回无隔离执行。U-004 的信任根、能力回调和真实运行证据仍未关闭。
