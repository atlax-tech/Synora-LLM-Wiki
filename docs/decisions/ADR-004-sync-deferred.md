# ADR-004 同步范围暂缓记录

状态：`ACCEPTED / RECORD_ONLY`；日期：2026-09-06；对应：P0-06、P0-10；上位决策：[ADR-H003](ADR-H003-free-local-services.md)。

## 记录

当前范围不实现 CloudKit、CKSyncEngine、iCloud 容器、设备复制、Companion 或 MusicKit/WeatherKit entitlement。P0-06 只做负向扫描，不从本地 revision、稳定 ID 或 operation sequence 推导同步协议。

## 证据

- `docs/p0/sync-negative-check.md` 定义扫描命令和 `DEFERRED / VERIFIED ABSENT` 语义。
- 当前产品与计划文档将同步和 iPhone 伴侣保留为 DEFERRED；本轮扫描未将其加入工程 target 或 entitlement。

## 影响与回滚

本地 operation log、备份、恢复、tombstone 和稳定 ID 继续服务单机可靠性，但不承诺跨设备复制或冲突合并。恢复同步必须取得新的用户决策并重开相应阶段/验收，不通过恢复旧文档隐式启用。

## 未关闭项

这是范围记录而非同步实现或互操作证明；closure HEAD `ce4a71c` 的产品代码负向扫描为 0 命中，后续阶段出口继续复扫。
