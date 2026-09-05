# ADR-001 平台基线与系统模型可用性

状态：`PROPOSED / CHANGES_REQUIRED`；日期：2026-09-06；对应：P0-10、U-001。

## 候选决策

- P0 探针以 macOS 26.0、Apple Silicon、Swift 6 为构建基线；当前工程配置是可复现的探针基线，不是最终产品最低系统承诺。
- Foundation Models 只通过可用性检查接入；不可用时必须保留本地编辑与确定性路径，不能把模型可用性当作启动条件。
- 最低系统版本、设备/地区矩阵和模型降级合同继续保持未决，待真实设备矩阵后再冻结。

## 证据

- `Config/Base.xcconfig` 将探针部署目标设为 macOS 26.0、架构设为 arm64。
- `App/SynoraP0ProbesApp.swift` 在可用 SDK 和 macOS 26.0 上读取 `SystemLanguageModel.default.isAvailable`，否则显示明确的不可用状态。
- `script/quality.sh` 默认 workspace 路径的 Debug/Release 工程构建、SwiftPM 测试和 XCUITest 在本机通过（编译缓存定向到 `/private/tmp`）；未运行多设备/地区矩阵。

## 取舍与回滚

保持当前探针配置可复现，避免在没有设备证据时伪造兼容承诺。若矩阵证明更低系统可行，降低产品目标并补等价降级；若证明不可行，保留 26.0 作为产品基线并在发布说明中记录。

## 未关闭项

Foundation Models 的真实设备、地区、账号和模型能力仍未验证；本草案不更新 U-001，也不授权产品发布。
