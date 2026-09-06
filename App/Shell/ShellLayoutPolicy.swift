import CoreGraphics

struct ShellLayoutResolution: Equatable, Sendable {
  let sidebarVisible: Bool
  let inspectorVisible: Bool
}

enum ShellLayoutPolicy {
  static let sidebarWidth: CGFloat = 180
  static let recordListWidth: CGFloat = 308
  static let editorMinimumWidth: CGFloat = 500
  static let inspectorWidth: CGFloat = 280
  // Native split-view chrome needs extra horizontal room beyond the content columns.
  static let fourColumnMinimumWidth: CGFloat = 1560
  // The native inspector needs extra room for split-view chrome at compact widths.
  static let inspectorWithListMinimumWidth: CGFloat = 1360

  static func resolve(
    availableWidth: CGFloat,
    desiredSidebarVisible: Bool,
    desiredInspectorVisible: Bool
  ) -> ShellLayoutResolution {
    guard desiredInspectorVisible else {
      return ShellLayoutResolution(sidebarVisible: desiredSidebarVisible, inspectorVisible: false)
    }

    if availableWidth >= fourColumnMinimumWidth {
      return ShellLayoutResolution(sidebarVisible: desiredSidebarVisible, inspectorVisible: true)
    }

    guard availableWidth >= inspectorWithListMinimumWidth else {
      return ShellLayoutResolution(sidebarVisible: desiredSidebarVisible, inspectorVisible: false)
    }

    return ShellLayoutResolution(sidebarVisible: false, inspectorVisible: true)
  }
}
