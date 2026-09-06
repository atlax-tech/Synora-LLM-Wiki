import Observation
import SwiftUI

@MainActor
@Observable
final class ShellModel {
  private(set) var availableContentWidth: CGFloat = 1440
  private(set) var effectiveSidebarVisible = true
  private(set) var effectiveInspectorVisible = true

  private(set) var desiredSidebarVisible: Bool
  private(set) var desiredInspectorVisible: Bool

  init(desiredSidebarVisible: Bool = true, desiredInspectorVisible: Bool = true) {
    self.desiredSidebarVisible = desiredSidebarVisible
    self.desiredInspectorVisible = desiredInspectorVisible
    reconcile(width: availableContentWidth)
  }

  func configure(desiredSidebarVisible: Bool, desiredInspectorVisible: Bool) {
    self.desiredSidebarVisible = desiredSidebarVisible
    self.desiredInspectorVisible = desiredInspectorVisible
    reconcile(width: availableContentWidth)
  }

  func setDesiredSidebarVisible(_ visible: Bool) {
    desiredSidebarVisible = visible
    reconcile(width: availableContentWidth)
  }

  func setDesiredInspectorVisible(_ visible: Bool) {
    desiredInspectorVisible = visible
    reconcile(width: availableContentWidth)
  }

  func reconcile(width: CGFloat) {
    availableContentWidth = max(width, 0)
    let resolution = ShellLayoutPolicy.resolve(
      availableWidth: availableContentWidth,
      desiredSidebarVisible: desiredSidebarVisible,
      desiredInspectorVisible: desiredInspectorVisible
    )
    effectiveSidebarVisible = resolution.sidebarVisible
    effectiveInspectorVisible = resolution.inspectorVisible
  }
}
