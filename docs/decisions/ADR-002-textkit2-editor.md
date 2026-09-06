# ADR-002 TextKit 2 编辑器基础

状态：`ACCEPTED FOR P0 / P2 VALIDATION`；日期：2026-09-06；对应：P0-04、P0-10。

## 候选决策

编辑器基础采用 `NSTextView(usingTextLayoutManager: true)`，通过 `NSViewRepresentable` 嵌入 SwiftUI；block 模型、持久化和业务用例保持在上层，不把数据库或 AI 逻辑放进视图。

## 证据

- `App/TextKit2Probe.swift` 创建 TextKit 2 `NSTextView`，并包含以中文、英文、组合字符、ZWJ emoji 和行边界为数据的 UTF-16 block range 检查；构建不会执行该检查。
- `SynoraP0Probes` Debug 构建和普通应用窗口 XCUITest 通过；probe 编辑器 UI 测试两次因系统未加载 accessibility 停止，因此不宣称运行时 fixture、第三方 IME、附件、撤销、复制粘贴、VoiceOver 或长文延迟已通过。

## 备选与后果

纯 SwiftUI `TextEditor` 不提供本探针需要的结构化富文本边界；Web 编辑器会增加运行时和数据边界。TextKit 2 保留 AppKit 输入法、选区和辅助功能入口，但需要后续处理 attachment、undo 和 block adapter 的复杂度。

## 回滚点与未关闭项

若真实 IME/附件/撤销验收出现可复现阻塞，先保留 block/domain 合同，再以失败样例评估适配层或受限降级；不得未经证据切换 TextKit 1。P2 负责手工矩阵、100k 字延迟和 VoiceOver。
