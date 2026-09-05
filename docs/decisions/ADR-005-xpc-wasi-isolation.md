# ADR-005 XPC 与 WASI Skill 隔离

状态：`PROPOSED / CHANGES_REQUIRED`；日期：2026-09-06；对应：P0-07、P0-10、U-004。

## 候选决策

可执行 Skill 通过独立 XPC service 承担生命周期边界，并在 WASI runtime 中运行；能力通过显式 broker policy 授权。默认不继承环境变量、文件 preopen 或网络；网络策略只允许明确声明的 loopback host。主应用是唯一可提交 ChangeSet 的边界。

## 证据

- `App/SynoraAgentServiceProbe.swift` 是独立 XPC target，拒绝非法、过期和已取消请求并返回结构化状态。
- `SynoraSkillProbe` 的 policy 单元测试覆盖未声明 capability 和非 loopback host；`bootstrap_wasmtime.sh` 固定 Wasmtime 48.0.1 官方 C API 包并校验 SHA-256。
- 当前 service 返回 `runtimeUnavailable`；未链接真实 Wasmtime C API，也未跑 guest、无 preopen、环境继承、崩溃重连、资源限制或 ≤100 ms 取消实验。

## 备选与后果

进程内执行更简单但会把 guest 崩溃和资源风险带入主应用；任意 shell 会突破能力合同。XPC/WASI 增加打包和 broker 工作，但保留主应用事务边界和可审计拒绝路径。

## 回滚点与未关闭项

若真实隔离矩阵失败，保留请求/结果合同和策略测试，暂停可执行 Skill 交付，不退回无隔离执行。U-004 的信任根、能力回调和真实运行证据仍未关闭。
