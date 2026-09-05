# ADR-006 Skill 包完整性与信任根

状态：`PROPOSED / UNRESOLVED`；日期：2026-09-06；对应：P0-09、P0-10、U-004。

## 候选决策

Skill 安装必须先解包到 staging，再做路径安全、包哈希、schema/compatibility 和权限预览，最后原子激活。SHA-256 只证明内容完整性；它不替代签名、信任根、撤销或来源审计。方案不依赖 Apple Developer 证书。

## 证据

- `docs/ARCHITECTURE.md` 已定义 manifest 至少包含版本、runtime、权限、域名、工具、包哈希与签名，并规定 staging → 校验 → 原子激活顺序。
- P0-07 bootstrap 对 Wasmtime 下载包做固定版本和 SHA-256 校验；当前没有 `.synoraskill` 安装器、签名验证器或信任根实现。
- `docs/p0/threat-model.md` 将依赖篡改、路径穿越和诊断泄露列为风险，相关动态验证仍为 `NOT_RUN`。

## 取舍与回滚

先冻结“完整性校验先于激活”和最小权限原则，暂不选择用户信任根、私有源或撤销协议。若 P6 无法建立可验证信任链，保持 Skill 禁用/只读安装状态，不把哈希展示误报为安全通过。

## 未关闭项

U-004 仍需用户可理解的信任来源、签名算法、撤销和降级攻击 fixture；本草案不能授权第三方包执行。
