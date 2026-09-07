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
  // The documented four-column content budget is 1268 pt. Reserve additional
  // room for native split-view chrome while still allowing the inspector at
  // the recommended 1440 pt content width.
  static let fourColumnMinimumWidth: CGFloat = 1400
  // The native inspector needs extra room for split-view chrome at compact widths.
  static let inspectorWithListMinimumWidth: CGFloat = 1360

  static func resolve(
    availableWidth: CGFloat,
    desiredSidebarVisible: Bool,
    desiredInspectorVisible: Bool
  ) -> ShellLayoutResolution {
    if desiredSidebarVisible {
      return ShellLayoutResolution(
        sidebarVisible: true,
        inspectorVisible: desiredInspectorVisible && availableWidth >= fourColumnMinimumWidth
      )
    }

    return ShellLayoutResolution(
      sidebarVisible: false,
      inspectorVisible: desiredInspectorVisible
        && availableWidth >= inspectorWithListMinimumWidth
    )
  }
}
