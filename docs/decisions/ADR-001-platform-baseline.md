# ADR-001 平台基线与系统模型可用性

状态：`PROPOSED / CHANGES_REQUIRED`；日期：2026-09-06；对应：P0-10、U-001。

## 候选决策

- P0 探针以 macOS 26.0、Apple Silicon、Swift 6 为构建基线；当前工程配置是可复现的探针基线，不是最终产品最低系统承诺。
- Foundation Models 只通过可用性检查接入；不可用时必须保留本地编辑与确定性路径，不能把模型可用性当作启动条件。
- 最低系统版本、设备/地区矩阵和模型降级合同继续保持未决，待真实设备矩阵后再冻结。

## 证据

- `Config/Base.xcconfig` 将探针部署目标设为 macOS 26.0、架构设为 arm64。
- `App/SynoraP0ProbesApp.swift` 在可用 SDK 和 macOS 26.0 上读取 `SystemLanguageModel.default.isAvailable`，否则显示明确的不可用状态。
- `script/quality.sh` 默认 workspace 路径的正式应用 Debug/Release、probe/XPC 集成构建、SwiftPM 测试和 XCUITest 在本机通过（产物定向到 `/private/tmp`）；未运行多设备/地区矩阵。

## 备选

- 支持 macOS 15+ 多版本基线：被否决。没有旧系统设备与真实矩阵证据，Foundation Models 与 Swift 6 工具链在旧系统上的行为无法核实，会伪造兼容承诺。
- 纯 SwiftPM 包、无 Xcode 工程：被否决。P0 需要应用沙箱、XPC service 嵌入、XCTest/XCUITest 和 entitlement 签名验证，这些能力依赖原生工程。
- 交叉平台抽象层（如 Qt/Electron）：被否决。产品是原生 macOS 记录与知识库，依赖 TextKit 2 与系统集成，抽象层会放大而非减少风险探针要验证的问题。

## 取舍与回滚

保持当前探针配置可复现，避免在没有设备证据时伪造兼容承诺。若矩阵证明更低系统可行，降低产品目标并补等价降级；若证明不可行，保留 26.0 作为产品基线并在发布说明中记录。

## 未关闭项

Foundation Models 的真实设备、地区、账号和模型能力仍未验证；本草案不更新 U-001，也不授权产品发布。
