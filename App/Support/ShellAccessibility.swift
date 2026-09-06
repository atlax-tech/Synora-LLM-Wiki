import Foundation

enum ShellAccessibilityID {
  static let window = "window"
  static let sidebar = "sidebar"
  static let recordList = "record-list"
  static let editor = "editor"
  static let inspector = "inspector"
  static let search = "search"
  static let recordKind = "record-kind"
  static let commandPalette = "command-palette"
  static let shellState = "shell-state"

  static func sidebarItem(_ item: SidebarItem) -> String {
    "sidebar-\(item.rawValue)"
  }

  static func record(_ id: UUID) -> String {
    "record-\(id.uuidString)"
  }

  static func state(_ state: ShellContentState) -> String {
    "shell-state-\(state.rawValue)"
  }
}
