import Foundation

enum ShellAccessibilityID {
  static let window = "window"
  static let sidebar = "sidebar"
  static let sidebarBrand = "sidebar-brand"
  static let toolbarSearchButton = "toolbar-search-button"
  static let toolbarSearchField = "toolbar-search-field"
  static let toolbarContext = "toolbar-context"
  static let toolbarSkills = "toolbar-skills"
  static let toolbarInspector = "toggle-inspector"
  static let toolbarCommandPalette = "command-palette-button"
  static let recordList = "record-list"
  static let editor = "editor"
  static let inspector = "inspector"
  static let search = "search"
  static let contentRoot = "shell-content-root"
  static let contentMetrics = "shell-content-metrics"
  static let recordKind = "record-kind"
  static let commandPalette = "command-palette"
  static let shellState = "shell-state"
  static let themeToggle = "theme-toggle"

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
