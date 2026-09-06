import Observation
import SwiftUI

@MainActor
@Observable
final class ShellModel {
  private(set) var availableContentWidth: CGFloat = 1440
  private(set) var effectiveSidebarVisible = true
  private(set) var effectiveInspectorVisible = true
  private(set) var commandPalettePresented = false
  private(set) var selectedRecordKind: RecordKind = .note

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

  func toggleSidebar() {
    setDesiredSidebarVisible(!desiredSidebarVisible)
  }

  func toggleInspector() {
    guard
      effectiveInspectorVisible
        || availableContentWidth >= ShellLayoutPolicy.inspectorWithListMinimumWidth
    else {
      return
    }
    setDesiredInspectorVisible(!effectiveInspectorVisible)
  }

  func setCommandPalettePresented(_ presented: Bool) {
    commandPalettePresented = presented
  }

  func toggleCommandPalette() {
    commandPalettePresented.toggle()
  }

  func selectRecordKind(_ kind: RecordKind) {
    selectedRecordKind = kind
  }

  var inspectorToggleEnabled: Bool {
    effectiveInspectorVisible
      || availableContentWidth >= ShellLayoutPolicy.inspectorWithListMinimumWidth
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
