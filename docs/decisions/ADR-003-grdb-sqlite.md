# ADR-003 GRDB 与 SQLite WAL 存储

状态：`PROPOSED / CHANGES_REQUIRED`；日期：2026-09-06；对应：P0-05、P0-10。

## 候选决策

运行时以 SQLite WAL 和 GRDB `DatabasePool` 作为本地事务源；领域包只依赖协议。每次保存把 revision 校验、operation append 和 projection 更新放在同一写事务，快照保存规范化状态和 SHA-256。

## 证据

- `Packages/SynoraCore/Package.swift` 精确固定 GRDB 7.10.0；`StoreProbe` 创建 WAL 数据库、operation log、snapshots 和 metadata 表。
- `SynoraStoreProbeTests` 证明正常保存、相同请求重复 operation ID 返回同一 receipt 且不改变 projection、不同请求复用 ID 被拒绝、过期 revision 不产生部分写入和快照校验；全量 SwiftPM 测试通过。
- 未运行 100k replay、进程终止、损坏快照、迁移回滚或 `SQLITE_FULL` 注入。

## 备选与后果

Core Data 或服务数据库会扩大本地依赖和离线边界；当前选择便于迁移、FTS5 和可读导出，但要求自行维护故障恢复、容量和 schema 兼容证据。

## 回滚点与未关闭项

领域协议和开放数据合同是回滚边界；若 P0 故障注入不能满足恢复门槛，应保留协议并重新评估存储实现。当前草案不把小型探针提升为生产恢复通过。
