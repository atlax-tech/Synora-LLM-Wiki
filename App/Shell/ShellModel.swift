import Observation
import SwiftUI

@MainActor
@Observable
final class ShellModel {
  private(set) var availableContentWidth: CGFloat = 1440
  private(set) var effectiveSidebarVisible = true
  private(set) var effectiveInspectorVisible = false
  private(set) var commandPalettePresented = false
  private(set) var selectedRecordKind: RecordKind = .note
  private(set) var searchQuery = ""
  private(set) var sidebarSelection: SidebarItem? = .today
  private(set) var inspectorMode: InspectorMode = .context
  private(set) var noteCount = 0
  private(set) var journalCount = 0
  private(set) var contentState: ShellContentState = .empty
  private(set) var canRetryContentLoad = false
  private(set) var recordsByKind: [RecordKind: [Record]] = [:]
  private(set) var selectedRecordIDs: [RecordKind: UUID?] = [.note: nil, .journal: nil]

  private(set) var desiredSidebarVisible: Bool
  private(set) var desiredInspectorVisible: Bool

  init(desiredSidebarVisible: Bool = true, desiredInspectorVisible: Bool = false) {
    self.desiredSidebarVisible = desiredSidebarVisible
    self.desiredInspectorVisible = desiredInspectorVisible
    reconcile(width: availableContentWidth)
  }

  func configure(desiredSidebarVisible: Bool, desiredInspectorVisible: Bool) {
    self.desiredSidebarVisible = desiredSidebarVisible
    self.desiredInspectorVisible = desiredInspectorVisible
    reconcile(width: availableContentWidth)
  }

  func restore(
    sidebarSelection: SidebarItem?,
    recordKind: RecordKind,
    inspectorMode: InspectorMode
  ) {
    self.sidebarSelection = sidebarSelection
    selectedRecordKind = recordKind
    self.inspectorMode = inspectorMode
  }

  func loadRecordsIfNeeded() {
    if recordsByKind.isEmpty {
      let records: [RecordKind: [Record]]
      if ShellEnvironment.fixture == "records" {
        records = [.note: RecordFixtureCatalog.notes, .journal: RecordFixtureCatalog.journals]
      } else {
        records = [.note: [], .journal: []]
      }

      recordsByKind = records
      noteCount = records[.note]?.count ?? 0
      journalCount = records[.journal]?.count ?? 0
      selectedRecordIDs = records.reduce(into: [RecordKind: UUID?]()) { result, entry in
        result[entry.key] = entry.value.first?.id
      }
    }

    applyContentStateOverride()
  }

  func retryContentLoad() {
    guard canRetryContentLoad else { return }
    canRetryContentLoad = false
    contentState = hasRecords ? .loaded : .empty
  }

  func records(for kind: RecordKind) -> [Record] {
    recordsByKind[kind] ?? []
  }

  func selectRecord(_ id: UUID?, in kind: RecordKind) {
    selectedRecordIDs[kind] = id
  }

  func selectedRecord(for kind: RecordKind) -> Record? {
    guard let id = selectedRecordIDs[kind] ?? nil else { return nil }
    return records(for: kind).first { $0.id == id }
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

  func setSearchQuery(_ query: String) {
    searchQuery = query
  }

  func selectSidebarItem(_ item: SidebarItem?) {
    sidebarSelection = item
    guard let item else { return }

    if let recordKind = item.recordKind {
      selectedRecordKind = recordKind
    }

  }

  func presentInspector(_ mode: InspectorMode) {
    inspectorMode = mode
    setDesiredInspectorVisible(true)
  }

  func setInspectorMode(_ mode: InspectorMode) {
    inspectorMode = mode
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

  private var hasRecords: Bool {
    recordsByKind.values.contains { !$0.isEmpty }
  }

  private func applyContentStateOverride() {
    if let rawState = ShellEnvironment.shellState,
      let requestedState = ShellContentState(rawValue: rawState)
    {
      contentState = requestedState
    } else {
      contentState = hasRecords ? .loaded : .empty
    }
    canRetryContentLoad = contentState == .error && ShellEnvironment.fixture == "error-retry"
  }
}
