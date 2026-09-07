import Foundation
import Observation
import SwiftUI
import SynoraAssets
import SynoraDomain
import SynoraEditorKit
import SynoraExport
import SynoraStore

enum EditorSaveState: Equatable {
  case saved
  case saving
  case conflict
  case failed

  var title: String {
    switch self {
    case .saved: "Saved"
    case .saving: "Saving…"
    case .conflict: "Conflict — changes kept locally"
    case .failed: "Save failed — changes kept locally"
    }
  }
}

enum RecordExportFormat: String, CaseIterable, Identifiable {
  case markdown
  case html
  case pdf
  case package

  var id: Self { self }

  var title: String {
    switch self {
    case .markdown: "Markdown"
    case .html: "HTML"
    case .pdf: "PDF"
    case .package: "Synora package"
    }
  }

  var fileExtension: String {
    switch self {
    case .markdown: "md"
    case .html: "html"
    case .pdf: "pdf"
    case .package: "synora"
    }
  }
}

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
  private(set) var editorTextByRecordID: [UUID: String] = [:]
  private(set) var editorTitleByRecordID: [UUID: String] = [:]
  private(set) var editorSelectionByRecordID: [UUID: NSRange] = [:]
  private(set) var editorSaveState: EditorSaveState = .saved
  private(set) var editorError: String?

  private(set) var desiredSidebarVisible: Bool
  private(set) var desiredInspectorVisible: Bool

  private let store: ProductStore?
  let assetStore: AssetStore?
  private var documentsByRecordID: [UUID: BlockDocument] = [:]
  private var editorSessions: [UUID: EditorSession] = [:]
  private var assetsByID: [UUID: Asset] = [:]
  private var loadTask: Task<Void, Never>?
  private var saveTasks: [UUID: Task<Void, Never>] = [:]

  init(desiredSidebarVisible: Bool = true, desiredInspectorVisible: Bool = false) {
    self.desiredSidebarVisible = desiredSidebarVisible
    self.desiredInspectorVisible = desiredInspectorVisible
    do {
      store = try ProductStore(path: ShellEnvironment.libraryPath)
    } catch {
      store = nil
    }
    assetStore = try? AssetStore(
      rootURL: URL(fileURLWithPath: ShellEnvironment.assetPath, isDirectory: true))
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
    guard recordsByKind.isEmpty else {
      applyContentStateOverride()
      return
    }

    if ShellEnvironment.fixture == "records" {
      apply(records: RecordFixtureCatalog.notes + RecordFixtureCatalog.journals, documents: nil)
      applyContentStateOverride()
      return
    }

    recordsByKind = [.note: [], .journal: []]
    selectedRecordIDs = [.note: nil, .journal: nil]
    applyContentStateOverride()

    guard let store else { return }
    loadTask = Task { [weak self, store] in
      do {
        let loaded = try await Task.detached(priority: .userInitiated) {
          let records = try store.records().map { record in
            (record, try store.document(recordID: record.id))
          }
          return (records, try store.assets())
        }.value
        guard let self else { return }
        self.applyPersisted(loaded.0, assets: loaded.1)
      } catch {
        guard let self else { return }
        self.contentState = .error
        self.canRetryContentLoad = true
      }
    }
  }

  func retryContentLoad() {
    guard canRetryContentLoad else { return }
    canRetryContentLoad = false
    recordsByKind = [:]
    loadRecordsIfNeeded()
  }

  func records(for kind: RecordKind) -> [Record] {
    recordsByKind[kind] ?? []
  }

  func selectRecord(_ id: UUID?, in kind: RecordKind) {
    selectedRecordIDs[kind] = id
    if let id, let record = records(for: kind).first(where: { $0.id == id }) {
      ensureEditorState(for: record)
    }
  }

  func selectedRecord(for kind: RecordKind) -> Record? {
    guard let id = selectedRecordIDs[kind] ?? nil else { return nil }
    return records(for: kind).first { $0.id == id }
  }

  func editorText(for record: Record) -> String {
    editorTextByRecordID[record.id] ?? text(for: documentsByRecordID[record.id])
  }

  func editorTitle(for record: Record) -> String {
    editorTitleByRecordID[record.id] ?? record.title
  }

  func editorSelection(for record: Record) -> NSRange {
    editorSelectionByRecordID[record.id] ?? NSRange(location: 0, length: 0)
  }

  func setEditorSelection(_ selection: NSRange, for record: Record) {
    guard selection.location >= 0, selection.length >= 0 else { return }
    editorSelectionByRecordID[record.id] = selection
  }

  var attachmentImportEnabled: Bool {
    store != nil && assetStore != nil && ShellEnvironment.fixture != "records"
  }

  func mediaBlocks(for record: Record) -> [Block] {
    documentsByRecordID[record.id]?.blocks.filter {
      $0.type.supportsAssetPlacements || $0.type == .link
    } ?? []
  }

  func asset(for id: UUID) -> Asset? { assetsByID[id] }

  func mediaAssets(for record: Record) -> [UUID: Asset] {
    let ids = mediaBlocks(for: record).flatMap { block -> [UUID] in
      guard case .assets(let placements)? = block.content else { return [] }
      return placements.map(\.assetID)
    }
    return ids.reduce(into: [:]) { result, id in
      if let asset = assetsByID[id] { result[id] = asset }
    }
  }

  func setEditorText(_ text: String, for record: Record) {
    ensureEditorState(for: record)
    guard editorTextByRecordID[record.id] != text else { return }
    editorTextByRecordID[record.id] = text
    if var session = editorSessions[record.id], let oldDocument = documentsByRecordID[record.id] {
      let oldText = TextStorageAdapter(document: oldDocument).text
      let change = textChange(from: oldText, to: text)
      if let document = try? session.apply(range: change.range, replacement: change.replacement) {
        editorSessions[record.id] = session
        documentsByRecordID[record.id] = document
      } else if let document = makeDocument(text: text, basedOn: oldDocument, recordID: record.id) {
        documentsByRecordID[record.id] = document
        editorSessions[record.id] = EditorSession(document: document)
      }
    } else if let document = makeDocument(text: text, basedOn: documentsByRecordID[record.id], recordID: record.id) {
      documentsByRecordID[record.id] = document
      editorSessions[record.id] = EditorSession(document: document)
    }
    scheduleSave(for: record.id)
  }

  func applyFormatting(
    _ style: InlineStyle,
    linkURL: String? = nil,
    for record: Record
  ) {
    mutateEditor(for: record) { session in
      try session.applyFormatting(
        style,
        in: self.editorSelection(for: record),
        linkURL: linkURL)
    }
  }

  func setBlockType(_ type: BlockType, for record: Record) {
    mutateEditor(for: record) { session in
      guard let blockID = self.blockID(at: self.editorSelection(for: record), in: session.document) else {
        throw EditorError.invalidSelection
      }
      return try session.execute(.setBlockType(type), blockID: blockID)
    }
  }

  func indentEditor(for record: Record) {
    mutateEditor(for: record) { session in
      guard let blockID = self.blockID(at: self.editorSelection(for: record), in: session.document) else {
        throw EditorError.invalidSelection
      }
      return try session.execute(.indent, blockID: blockID)
    }
  }

  func outdentEditor(for record: Record) {
    mutateEditor(for: record) { session in
      guard let blockID = self.blockID(at: self.editorSelection(for: record), in: session.document) else {
        throw EditorError.invalidSelection
      }
      return try session.execute(.outdent, blockID: blockID)
    }
  }

  func setCalloutStyle(_ style: CalloutStyle, for record: Record) {
    mutateEditor(for: record) { session in
      guard let blockID = self.blockID(at: self.editorSelection(for: record), in: session.document) else {
        throw EditorError.invalidSelection
      }
      return try session.setCalloutStyle(style, in: blockID)
    }
  }

  func addTableRow(for record: Record) {
    mutateEditor(for: record) { session in
      guard let blockID = self.blockID(at: self.editorSelection(for: record), in: session.document) else {
        throw EditorError.invalidSelection
      }
      return try session.execute(.insertTableRow(at: nil), blockID: blockID)
    }
  }

  func addTableColumn(for record: Record) {
    mutateEditor(for: record) { session in
      guard let blockID = self.blockID(at: self.editorSelection(for: record), in: session.document) else {
        throw EditorError.invalidSelection
      }
      return try session.execute(.insertTableColumn(at: nil), blockID: blockID)
    }
  }

  func handleReturn(in selection: NSRange, for record: Record) -> Bool {
    guard selection.length == 0 else { return false }
    ensureEditorState(for: record)
    guard var session = editorSessions[record.id],
      let document = documentsByRecordID[record.id],
      let blockID = blockID(at: selection, in: document),
      let range = TextStorageAdapter(document: document).range(for: blockID)
    else { return false }
    let offset = max(0, selection.location - range.location)
    do {
      let updated = try session.pressReturn(in: blockID, atUTF16Offset: offset)
      editorSessions[record.id] = session
      documentsByRecordID[record.id] = updated
      editorTextByRecordID[record.id] = TextStorageAdapter(document: updated).text
      editorSelectionByRecordID[record.id] = NSRange(
        location: min(selection.location + 1, (editorTextByRecordID[record.id]! as NSString).length),
        length: 0)
      scheduleSave(for: record.id)
      return true
    } catch {
      return false
    }
  }

  func handleBackspace(in selection: NSRange, for record: Record) -> Bool {
    guard selection.length == 0, selection.location > 0 else { return false }
    ensureEditorState(for: record)
    guard var session = editorSessions[record.id],
      let document = documentsByRecordID[record.id],
      let blockID = blockID(at: selection, in: document),
      let range = TextStorageAdapter(document: document).range(for: blockID)
    else { return false }
    let offset = max(0, selection.location - range.location)
    guard offset == 0 else { return false }
    do {
      let updated = try session.pressBackspace(in: blockID, atUTF16Offset: offset)
      guard updated != document else { return false }
      editorSessions[record.id] = session
      documentsByRecordID[record.id] = updated
      editorTextByRecordID[record.id] = TextStorageAdapter(document: updated).text
      editorSelectionByRecordID[record.id] = NSRange(location: selection.location - 1, length: 0)
      scheduleSave(for: record.id)
      return true
    } catch {
      return false
    }
  }

  func applySlashCommand(_ command: SlashCommand, for record: Record) {
    mutateEditor(for: record) { session in
      guard let blockID = self.blockID(at: self.editorSelection(for: record), in: session.document) else {
        throw EditorError.invalidSelection
      }
      return try session.applySlashCommand(command, in: blockID)
    }
  }

  func applyMarkdownShortcut(for record: Record) {
    mutateEditor(for: record) { session in
      guard let blockID = self.blockID(at: self.editorSelection(for: record), in: session.document) else {
        throw EditorError.invalidSelection
      }
      return try session.applyMarkdownShortcut(in: blockID)
    }
  }

  func toggleTask(for record: Record) {
    mutateEditor(for: record) { session in
      guard let blockID = self.blockID(at: self.editorSelection(for: record), in: session.document) else {
        throw EditorError.invalidSelection
      }
      return try session.execute(.toggleTask, blockID: blockID)
    }
  }

  func toggleCollapse(for record: Record) {
    mutateEditor(for: record) { session in
      guard let blockID = self.blockID(at: self.editorSelection(for: record), in: session.document) else {
        throw EditorError.invalidSelection
      }
      return try session.toggleCollapse(in: blockID)
    }
  }

  func undoEditor(for record: Record) {
    mutateEditor(for: record) { try $0.undo() }
  }

  func redoEditor(for record: Record) {
    mutateEditor(for: record) { try $0.redo() }
  }

  func replaceAll(query: String, with replacement: String, for record: Record) {
    mutateEditor(for: record) { try $0.replaceAll(query: query, with: replacement) }
  }

  func setAssetCaption(
    _ caption: String,
    assetID: UUID,
    in blockID: UUID,
    for record: Record
  ) {
    mutateEditor(for: record) { try $0.setAssetCaption(caption, for: assetID, in: blockID) }
  }

  func reorderAttachment(
    _ assetID: UUID,
    in blockID: UUID,
    before targetAssetID: UUID?,
    for record: Record
  ) {
    mutateEditor(for: record) {
      try $0.reorderAsset(assetID, in: blockID, before: targetAssetID)
    }
  }

  func setMediaLayout(_ layout: MediaLayout, in blockID: UUID, for record: Record) {
    mutateEditor(for: record) { try $0.setMediaLayout(layout, in: blockID) }
  }

  func export(
    _ format: RecordExportFormat,
    record: Record,
    to destinationURL: URL
  ) throws {
    guard let document = documentsByRecordID[record.id] else {
      throw ExportError.invalidDocument
    }
    let domainRecord = makeDomainRecord(from: record, title: editorTitle(for: record))
    let service = RecordExportService(assetStore: assetStore)
    switch format {
    case .markdown:
      try service.markdown(record: domainRecord, document: document)
        .write(to: destinationURL, atomically: true, encoding: .utf8)
    case .html:
      try service.html(record: domainRecord, document: document)
        .write(to: destinationURL, atomically: true, encoding: .utf8)
    case .pdf:
      try service.exportPDF(record: domainRecord, document: document, to: destinationURL)
    case .package:
      try service.exportPackage(
        record: domainRecord,
        document: document,
        assets: mediaAssets(for: record).map(\.value),
        to: destinationURL)
    }
  }

  func setEditorTitle(_ title: String, for record: Record) {
    ensureEditorState(for: record)
    guard editorTitleByRecordID[record.id] != title else { return }
    editorTitleByRecordID[record.id] = title
    scheduleSave(for: record.id)
  }

  func saveEditorNow(for record: Record) {
    scheduleSave(for: record.id, delay: 0)
  }

  func importAttachment(from url: URL, for record: Record) {
    guard attachmentImportEnabled, let store, let assetStore,
      self.record(withID: record.id) != nil,
      documentsByRecordID[record.id] != nil
    else {
      editorSaveState = .failed
      return
    }

    saveTasks[record.id]?.cancel()
    let hasSecurityScope = url.startAccessingSecurityScopedResource()
    Task { [weak self, store, assetStore] in
      defer {
        if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
      }
      do {
        let asset = try await Task.detached(priority: .userInitiated) {
          try await assetStore.importFile(at: url)
        }.value
        guard let self,
          let current = self.record(withID: record.id),
          let baseDocument = self.documentsByRecordID[record.id]
        else {
          throw ProductStoreError.missingRecord
        }
        let title = self.editorTitle(for: current)
        let blockID = UUID()
        let blockType = Self.mediaBlockType(for: assetStore.mediaKind(for: asset))
        var document = try baseDocument.creating(blockType, id: blockID)
        document = try document.placingAsset(
          AssetPlacement(assetID: asset.id), in: blockID)
        self.saveMediaDocument(
          record: current,
          title: title,
          document: document,
          asset: asset,
          store: store,
          assetStore: assetStore)
      } catch is CancellationError {
        return
      } catch is RevisionError {
        self?.editorSaveState = .conflict
      } catch {
        self?.editorSaveState = .failed
        if let referenced = try? store.assets() { try? assetStore.recover(referencedAssets: referenced) }
      }
    }
  }

  func replaceAttachment(
    from url: URL,
    assetID: UUID,
    in blockID: UUID,
    for record: Record
  ) {
    guard attachmentImportEnabled, let store, let assetStore,
      self.record(withID: record.id) != nil,
      documentsByRecordID[record.id]?.assetPlacement(assetID, in: blockID) != nil
    else {
      editorSaveState = .failed
      return
    }

    saveTasks[record.id]?.cancel()
    let hasSecurityScope = url.startAccessingSecurityScopedResource()
    Task { [weak self, store, assetStore] in
      defer {
        if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
      }
      do {
        let asset = try await Task.detached(priority: .userInitiated) {
          try await assetStore.importFile(at: url)
        }.value
        guard let self,
          let current = self.record(withID: record.id),
          let document = self.documentsByRecordID[record.id],
          let placement = document.assetPlacement(assetID, in: blockID)
        else {
          throw ProductStoreError.missingRecord
        }
        let title = self.editorTitle(for: current)
        let replacement = AssetPlacement(
          assetID: asset.id,
          order: placement.order,
          caption: placement.caption,
          crop: placement.crop)
        let updated = try document.replacingAsset(assetID, with: replacement, in: blockID)
        self.saveMediaDocument(
          record: current,
          title: title,
          document: updated,
          asset: asset,
          store: store,
          assetStore: assetStore)
      } catch is CancellationError {
        return
      } catch is RevisionError {
        self?.editorSaveState = .conflict
      } catch {
        self?.editorSaveState = .failed
        if let referenced = try? store.assets() { try? assetStore.recover(referencedAssets: referenced) }
      }
    }
  }

  func removeAttachment(assetID: UUID, from blockID: UUID, for record: Record) {
    guard let store, let assetStore,
      let current = self.record(withID: record.id),
      let document = documentsByRecordID[record.id],
      document.assetPlacement(assetID, in: blockID) != nil
    else {
      editorSaveState = .failed
      return
    }
    do {
      let updated = try document.removingAsset(assetID, from: blockID)
      let title = editorTitle(for: current)
      saveMediaDocument(
        record: current,
        title: title,
        document: updated,
        asset: nil,
        store: store,
        assetStore: assetStore)
    } catch {
      editorSaveState = .failed
    }
  }

  func createRecord(kind requestedKind: RecordKind? = nil) {
    let kind = requestedKind ?? selectedRecordKind
    if ShellEnvironment.fixture == "records" || store == nil {
      let id = UUID()
      let now = Date()
      let record = Record(
        id: id, kind: kind, title: "Untitled", summary: "", modifiedAt: now,
        revision: 0, journalDate: kind == .journal ? now : nil)
      guard let document = try? BlockDocument(
        recordID: id,
        blocks: [Block(id: UUID(), recordID: id, position: 0, text: "")])
      else {
        editorSaveState = .failed
        return
      }
      append(record: record, document: document)
      selectedRecordKind = kind
      selectedRecordIDs[kind] = id
      return
    }

    guard let store else { return }
    Task { [weak self, store] in
      do {
        let result = try await Task.detached(priority: .userInitiated) {
          try store.create(title: "Untitled", kind: kind == .journal ? .journal : .note,
                           journalDate: kind == .journal ? Date() : nil)
        }.value
        guard let self else { return }
        let document = try store.document(recordID: result.record.id)
        self.append(record: Record(domain: result.record, summary: ""), document: document)
        self.selectedRecordKind = kind
        self.selectedRecordIDs[kind] = result.record.id
      } catch {
        self?.editorSaveState = .failed
      }
    }
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

  private func applyPersisted(
    _ loaded: [(SynoraDomain.Record, BlockDocument)],
    assets: [Asset]
  ) {
    assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
    apply(
      records: loaded.map { Record(domain: $0.0, summary: $0.1.children().first?.text ?? "") },
      documents: loaded.map(\.1)
    )
    applyContentStateOverride()
  }

  private func apply(records: [Record], documents: [BlockDocument]?) {
    if documents == nil { assetsByID = [:] }
    var grouped: [RecordKind: [Record]] = [.note: [], .journal: []]
    for record in records { grouped[record.kind, default: []].append(record) }
    recordsByKind = grouped
    noteCount = grouped[.note]?.count ?? 0
    journalCount = grouped[.journal]?.count ?? 0

    var documentByID: [UUID: BlockDocument] = [:]
    if let documents {
      documentByID = Dictionary(uniqueKeysWithValues: documents.map { ($0.recordID, $0) })
    } else {
      for record in records {
        documentByID[record.id] = try? BlockDocument(
          recordID: record.id,
          blocks: [Block(id: UUID(), recordID: record.id, position: 0, text: record.summary)]
        )
      }
    }
    documentsByRecordID = documentByID
    editorSessions = Dictionary(uniqueKeysWithValues: documentByID.map { id, document in
      (id, EditorSession(document: document))
    })
    editorSelectionByRecordID = Dictionary(uniqueKeysWithValues: records.map {
      ($0.id, NSRange(location: 0, length: 0))
    })
    editorTextByRecordID = Dictionary(uniqueKeysWithValues: records.map {
      ($0.id, text(for: documentByID[$0.id]))
    })
    editorTitleByRecordID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.title) })

    for kind in RecordKind.allCases {
      let ids = Set(grouped[kind, default: []].map(\.id))
      let selected = selectedRecordIDs[kind] ?? nil
      selectedRecordIDs[kind] = selected.flatMap { ids.contains($0) ? $0 : nil }
        ?? grouped[kind]?.first?.id
    }
  }

  private func append(record: Record, document: BlockDocument) {
    var records = recordsByKind
    records[record.kind, default: []].append(record)
    documentsByRecordID[record.id] = document
    editorTextByRecordID[record.id] = text(for: document)
    editorTitleByRecordID[record.id] = record.title
    editorSessions[record.id] = EditorSession(document: document)
    editorSelectionByRecordID[record.id] = NSRange(location: 0, length: 0)
    apply(records: records.values.flatMap { $0 }, documents: Array(documentsByRecordID.values))
    contentState = .loaded
  }

  private func ensureEditorState(for record: Record) {
    if editorTitleByRecordID[record.id] == nil { editorTitleByRecordID[record.id] = record.title }
    if editorTextByRecordID[record.id] == nil {
      editorTextByRecordID[record.id] = text(for: documentsByRecordID[record.id])
    }
    if editorSessions[record.id] == nil, let document = documentsByRecordID[record.id] {
      editorSessions[record.id] = EditorSession(document: document)
    }
  }

  @discardableResult
  private func mutateEditor(
    for record: Record,
    _ operation: (inout EditorSession) throws -> BlockDocument
  ) -> BlockDocument? {
    ensureEditorState(for: record)
    guard var session = editorSessions[record.id] else {
      editorError = "Editor document is unavailable"
      editorSaveState = .failed
      return nil
    }
    do {
      let document = try operation(&session)
      editorSessions[record.id] = session
      documentsByRecordID[record.id] = document
      editorTextByRecordID[record.id] = text(for: document)
      editorError = nil
      scheduleSave(for: record.id)
      return document
    } catch {
      editorError = String(describing: error)
      editorSaveState = .failed
      return nil
    }
  }

  private func blockID(at selection: NSRange, in document: BlockDocument) -> UUID? {
    let ranges = TextStorageAdapter(document: document).ranges
    guard !ranges.isEmpty else { return nil }
    let offset = max(selection.location, 0)
    return ranges.first(where: { offset <= NSMaxRange($0.range) })?.blockID ?? ranges.last?.blockID
  }

  private func textChange(from old: String, to new: String)
    -> (range: NSRange, replacement: String)
  {
    let oldValue = old as NSString
    let newValue = new as NSString
    var prefix = 0
    while prefix < oldValue.length, prefix < newValue.length,
      oldValue.character(at: prefix) == newValue.character(at: prefix) {
      prefix += 1
    }
    var suffix = 0
    while suffix < oldValue.length - prefix, suffix < newValue.length - prefix,
      oldValue.character(at: oldValue.length - suffix - 1)
        == newValue.character(at: newValue.length - suffix - 1) {
      suffix += 1
    }
    let oldEnd = oldValue.length - suffix
    let newEnd = newValue.length - suffix
    return (
      NSRange(location: prefix, length: oldEnd - prefix),
      newValue.substring(with: NSRange(location: prefix, length: newEnd - prefix))
    )
  }

  private func saveMediaDocument(
    record: Record,
    title: String,
    document: BlockDocument,
    asset: Asset?,
    store: ProductStore,
    assetStore: AssetStore
  ) {
    saveTasks[record.id]?.cancel()
    if var session = editorSessions[record.id] {
      _ = session.adopt(document)
      editorSessions[record.id] = session
    } else {
      editorSessions[record.id] = EditorSession(document: document)
    }
    documentsByRecordID[record.id] = document
    editorTextByRecordID[record.id] = TextStorageAdapter(document: document).text
    editorSaveState = .saving
    let domainRecord = makeDomainRecord(from: record, title: title)
    let expectedRevision = record.revision
    saveTasks[record.id] = Task { [weak self, store, assetStore] in
      do {
        let receipt = try await Task.detached(priority: .userInitiated) {
          if let asset {
            return try store.saveAsset(
              asset,
              record: domainRecord,
              document: document,
              expectedRevision: expectedRevision)
          }
          return try store.save(
            record: domainRecord,
            document: document,
            expectedRevision: expectedRevision)
        }.value
        guard let self else { return }
        var savedDomainRecord = domainRecord
        savedDomainRecord.revision = receipt.revision
        if let asset { self.assetsByID[asset.id] = asset }
        self.replaceRecord(
          Record(
            domain: savedDomainRecord,
            summary: document.children().first?.text ?? "",
            thumbnailName: record.thumbnailName))
        if self.documentsByRecordID[record.id] == document,
          self.editorTitleByRecordID[record.id] == title
        {
          self.editorSaveState = .saved
        } else {
          self.scheduleSave(for: record.id, delay: 0)
        }
      } catch is RevisionError {
        self?.editorSaveState = .conflict
      } catch is CancellationError {
      } catch {
        self?.editorSaveState = .failed
        if let referenced = try? store.assets() {
          try? assetStore.recover(referencedAssets: referenced)
        }
      }
    }
  }

  private func scheduleSave(for recordID: UUID, delay: UInt64 = 250_000_000) {
    saveTasks[recordID]?.cancel()
    guard let record = record(withID: recordID), let document = documentsByRecordID[recordID] else {
      return
    }
    let title = editorTitleByRecordID[recordID] ?? record.title
    let text = editorTextByRecordID[recordID] ?? text(for: document)
    editorSaveState = .saving

    guard let store, ShellEnvironment.fixture != "records" else {
      editorSaveState = .saved
      return
    }

    let domainRecord = makeDomainRecord(from: record, title: title)
    let expectedRevision = record.revision
    saveTasks[recordID] = Task { [weak self, store] in
      do {
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        guard !Task.isCancelled else { return }
        let saved = try await Task.detached(priority: .userInitiated) {
          let receipt = try store.save(
            record: domainRecord,
            document: document,
            expectedRevision: expectedRevision
          )
          guard let record = try store.record(id: recordID) else {
            throw ProductStoreError.missingRecord
          }
          return (record, receipt.revision)
        }.value
        // A cancelled delay may still have committed in the detached store
        // task. Apply its revision before scheduling the newer local draft.
        guard let self else { return }
        self.applySaveSuccess(
          recordID: recordID,
          savedRecord: saved.0,
          revision: saved.1,
          capturedTitle: title,
          capturedText: text,
          capturedDocument: document
        )
      } catch is RevisionError {
        self?.editorSaveState = .conflict
      } catch is CancellationError {
      } catch {
        self?.editorSaveState = .failed
      }
    }
  }

  private func applySaveSuccess(
    recordID: UUID,
    savedRecord: SynoraDomain.Record,
    revision: Int,
    capturedTitle: String,
    capturedText: String,
    capturedDocument: BlockDocument
  ) {
    replaceRecord(
      Record(
        domain: savedRecord,
        summary: documentsByRecordID[recordID]?.children().first?.text ?? "",
        thumbnailName: record(withID: recordID)?.thumbnailName
      )
    )
    if editorTitleByRecordID[recordID] == capturedTitle,
      editorTextByRecordID[recordID] == capturedText,
      documentsByRecordID[recordID] == capturedDocument
    {
      editorSaveState = .saved
    } else {
      scheduleSave(for: recordID, delay: 0)
    }
    _ = revision
  }

  private func replaceRecord(_ replacement: Record) {
    guard let current = record(withID: replacement.id) else { return }
    recordsByKind[current.kind] = records(for: current.kind).map {
      $0.id == replacement.id ? replacement : $0
    }
    noteCount = records(for: .note).count
    journalCount = records(for: .journal).count
  }

  private func record(withID id: UUID) -> Record? {
    recordsByKind.values.lazy.flatMap { $0 }.first { $0.id == id }
  }

  private func makeDomainRecord(from record: Record, title: String) -> SynoraDomain.Record {
    var metadata = record.metadata
    metadata["modifiedAt"] = String(Date().timeIntervalSince1970)
    if let thumbnailName = record.thumbnailName { metadata["thumbnailName"] = thumbnailName }
    return SynoraDomain.Record(
      id: record.id,
      title: title,
      revision: record.revision,
      kind: record.kind == .journal ? .journal : .note,
      journalDate: record.journalDate,
      metadata: metadata
    )
  }

  private func makeDocument(text: String, basedOn document: BlockDocument?, recordID: UUID)
    -> BlockDocument?
  {
    guard let document else {
      let blocks = text.components(separatedBy: "\n").enumerated().map { index, line in
        Block(id: UUID(), recordID: recordID, position: index, text: line)
      }
      return try? BlockDocument(recordID: recordID, blocks: blocks)
    }
    let adapter = TextStorageAdapter(document: document)
    guard adapter.text != text else { return document }
    let old = adapter.text as NSString
    let new = text as NSString
    var prefix = 0
    while prefix < old.length, prefix < new.length,
      old.character(at: prefix) == new.character(at: prefix) {
      prefix += 1
    }
    while prefix > 0,
      (!isComposedBoundary(prefix, in: old) || !isComposedBoundary(prefix, in: new)) {
      prefix -= 1
    }

    var suffix = 0
    while suffix < old.length - prefix, suffix < new.length - prefix,
      old.character(at: old.length - suffix - 1) == new.character(at: new.length - suffix - 1) {
      suffix += 1
    }
    while suffix > 0 {
      let oldEnd = old.length - suffix
      let newEnd = new.length - suffix
      guard isComposedBoundary(oldEnd, in: old), isComposedBoundary(newEnd, in: new) else {
        suffix -= 1
        continue
      }
      break
    }

    let oldEnd = old.length - suffix
    let newEnd = new.length - suffix
    let range = NSRange(location: prefix, length: oldEnd - prefix)
    let replacement = new.substring(with: NSRange(location: prefix, length: newEnd - prefix))
    return try? adapter.applying(range: range, replacement: replacement)
  }

  private func isComposedBoundary(_ offset: Int, in text: NSString) -> Bool {
    guard offset > 0, offset < text.length else { return true }
    let range = text.rangeOfComposedCharacterSequence(at: offset)
    return range.location == offset || NSMaxRange(range) == offset
  }

  private func text(for document: BlockDocument?) -> String {
    document.map { TextStorageAdapter(document: $0).text } ?? ""
  }

  private static func mediaBlockType(for kind: AssetPreviewKind) -> BlockType {
    switch kind {
    case .image: .image
    case .video: .video
    case .audio: .audio
    case .pdf: .pdf
    case .file: .file
    }
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
