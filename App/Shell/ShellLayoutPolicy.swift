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
  static let fourColumnMinimumWidth: CGFloat = 1268
  static let inspectorWithListMinimumWidth: CGFloat = 1088

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
