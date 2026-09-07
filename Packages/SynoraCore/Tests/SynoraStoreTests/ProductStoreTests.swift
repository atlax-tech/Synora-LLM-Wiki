import Foundation
import SynoraDomain
import Testing

@testable import SynoraStore

@Test
func productStoreCommitsDocumentAtomicallyAndReopens() throws {
  let path = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-product-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("library.sqlite").path
  defer { try? FileManager.default.removeItem(atPath: path) }

  let store = try ProductStore(path: path)
  let recordID = UUID()
  let blockID = UUID()
  let record = Record(
    id: recordID, title: "第一篇", kind: .journal, journalDate: Date(timeIntervalSince1970: 42),
    metadata: ["mood": "calm"])
  let document = try BlockDocument(
    recordID: recordID,
    blocks: [Block(
      id: blockID, recordID: recordID, position: 0, text: "中文输入🙂", type: .paragraph,
      attributes: ["emphasis": "true"])])

  let receipt = try store.save(record: record, document: document, expectedRevision: 0)
  #expect(receipt.revision == 1)
  #expect(try store.record(id: recordID)?.metadata["mood"] == "calm")
  #expect(try store.document(recordID: recordID) == document)
  #expect(try store.operationCount() == 1)
  try store.verifyIntegrity()

  let reopened = try ProductStore(path: path)
  #expect(try reopened.records(kind: .journal).map(\.id) == [recordID])
  #expect(try reopened.document(recordID: recordID).blocks.map(\.id) == [blockID])
}

@Test
func productStoreRejectsStaleRevisionAndReplaysSameRequest() throws {
  let path = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-product-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("library.sqlite").path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let operationID = UUID()
  let store = try ProductStore(path: path)
  let recordID = UUID()
  let record = Record(id: recordID, title: "first")
  let document = try BlockDocument(recordID: recordID)
  let first = try store.save(
    record: record, document: document, expectedRevision: 0, operationID: operationID)
  #expect(try store.save(
    record: record, document: document, expectedRevision: 0, operationID: operationID) == first)
  #expect(try store.operationCount() == 1)
  #expect(throws: RevisionError.stale(expected: 0, actual: 1)) {
    try store.save(record: record, document: document, expectedRevision: 0)
  }
  #expect(try store.operationCount() == 1)
  #expect(throws: ProductStoreError.operationConflict) {
    try store.save(
      record: Record(id: recordID, title: "different"), document: document,
      expectedRevision: 0, operationID: operationID)
  }
}

@Test
func productStoreUndoRedoUsesNewAuditedTransactions() throws {
  let path = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-product-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("library.sqlite").path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let store = try ProductStore(path: path)
  let recordID = UUID()
  let first = Record(id: recordID, title: "first")
  let document = try BlockDocument(recordID: recordID)
  _ = try store.save(record: first, document: document, expectedRevision: 0)
  let second = Record(id: recordID, title: "second")
  _ = try store.save(record: second, document: document, expectedRevision: 1)

  _ = try store.undo(recordID: recordID)
  #expect(try store.record(id: recordID)?.title == "first")
  _ = try store.redo(recordID: recordID)
  #expect(try store.record(id: recordID)?.title == "second")
  #expect(try store.operationCount() == 4)
  try store.verifyIntegrity()
}

@Test
func productStoreUndoRedoRebuildsAcrossConsecutiveEditsAndReopen() throws {
  let path = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-product-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("library.sqlite").path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let store = try ProductStore(path: path)
  let recordID = UUID()
  let document = try BlockDocument(recordID: recordID)
  _ = try store.save(record: Record(id: recordID, title: "one"), document: document, expectedRevision: 0)
  _ = try store.save(record: Record(id: recordID, title: "two"), document: document, expectedRevision: 1)
  _ = try store.save(record: Record(id: recordID, title: "three"), document: document, expectedRevision: 2)

  _ = try store.undo(recordID: recordID)
  _ = try store.undo(recordID: recordID)
  #expect(try store.record(id: recordID)?.title == "one")

  let reopened = try ProductStore(path: path)
  _ = try reopened.redo(recordID: recordID)
  #expect(try reopened.record(id: recordID)?.title == "two")
  _ = try reopened.save(
    record: Record(id: recordID, title: "branch"), document: document, expectedRevision: 6)
  #expect(throws: ProductStoreError.noRedo) { try reopened.redo(recordID: recordID) }
}

@Test
func productStoreSnapshotIsValid() throws {
  let path = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-product-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("library.sqlite").path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let store = try ProductStore(path: path)
  let recordID = UUID()
  _ = try store.save(
    record: Record(id: recordID, title: "snapshot"),
    document: try BlockDocument(recordID: recordID), expectedRevision: 0)
  let snapshot = try store.snapshot()
  #expect(snapshot.isValid())
  #expect(snapshot.upToSequence == 1)
}

@Test
func productStorePreviewsAndRestoresHistoryWithoutErasingLog() throws {
  let path = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-product-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("library.sqlite").path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let store = try ProductStore(path: path)
  let recordID = UUID()
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(id: UUID(), recordID: recordID, position: 0, text: "first")
  ])
  _ = try store.save(record: Record(id: recordID, title: "first"), document: document, expectedRevision: 0)
  let secondDocument = try document.splitting(
    id: document.blocks[0].id, atUTF16Offset: 5, newID: UUID())
  _ = try store.save(record: Record(id: recordID, title: "second"), document: secondDocument, expectedRevision: 1)
  let history = try store.history(recordID: recordID)
  #expect(history.count == 2)
  let firstVersion = try store.version(recordID: recordID, sequence: history.last!.sequence)
  #expect(firstVersion?.record.title == "first")
  _ = try store.restore(recordID: recordID, sequence: history.last!.sequence)
  #expect(try store.record(id: recordID)?.title == "first")
  #expect(try store.operationCount() == 3)
  try store.verifyIntegrity()
}

@Test
func productStoreWritesAutomaticSnapshotAtTheConfiguredInterval() throws {
  let path = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-product-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("library.sqlite").path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let store = try ProductStore(path: path)
  let recordID = UUID()
  let document = try BlockDocument(recordID: recordID)
  for revision in 0..<100 {
    _ = try store.save(
      record: Record(id: recordID, title: "\(revision)"),
      document: document,
      expectedRevision: revision
    )
  }
  #expect(try store.latestSnapshot()?.upToSequence == 100)
  #expect(try store.latestSnapshot()?.isValid() == true)
}

@Test
func productStoreTemplatesCopyTreeIDsAndRefuseSilentReplacement() throws {
  let path = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-product-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("library.sqlite").path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let store = try ProductStore(path: path)
  let recordID = UUID()
  let templateRecordID = UUID()
  let templateParentID = UUID()
  let templateChildID = UUID()
  let template = RecordTemplate(
    id: UUID(), name: "Daily", kind: .journal,
    blocks: [
      Block(id: templateParentID, recordID: templateRecordID, position: 0, text: "Today", type: .toggle),
      Block(id: templateChildID, recordID: templateRecordID, position: 0, text: "Plan", parentID: templateParentID),
    ], metadata: ["template": "daily"])
  try store.saveTemplate(template)
  #expect(try store.templates().count == 1)
  _ = try store.save(
    record: Record(id: recordID, title: "Empty"),
    document: try BlockDocument(recordID: recordID),
    expectedRevision: 0)
  let receipt = try store.applyTemplate(template, to: recordID, expectedRevision: 1)
  #expect(receipt.revision == 2)
  let document = try store.document(recordID: recordID)
  #expect(document.blocks.count == 2)
  #expect(Set(document.blocks.map(\.id)).isDisjoint(with: Set(template.blocks.map(\.id))))
  #expect(document.children().first?.type == .toggle)
  #expect(document.children().first.flatMap { document.block(id: $0.id) } != nil)
  #expect(try store.record(id: recordID)?.kind == .journal)

  _ = try store.save(
    record: Record(id: recordID, title: "Changed", kind: .journal),
    document: document,
    expectedRevision: 2)
  #expect(throws: ProductStoreError.templateWouldReplaceContent) {
    try store.applyTemplate(template, to: recordID, expectedRevision: 3)
  }
}

@Test
func productStoreEditsTemplatesAndMetadataThroughTheSameTransactionPath() throws {
  let path = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-product-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("library.sqlite").path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let store = try ProductStore(path: path)
  let templateID = UUID()
  let template = RecordTemplate(id: templateID, name: "Blank", kind: .note)
  try store.saveTemplate(template)
  var edited = template
  edited.name = "Edited"
  edited.metadata = ["tag": "work"]
  try store.saveTemplate(edited)
  #expect(try store.template(id: templateID) == edited)
  try store.deleteTemplate(id: templateID)
  #expect(try store.template(id: templateID) == nil)

  let (record, _) = try store.create(title: "Metadata")
  _ = try store.updateMetadata(
    recordID: record.id, metadata: ["favorite": "true", "tag": "work"], expectedRevision: 1)
  #expect(try store.record(id: record.id)?.metadata == ["favorite": "true", "tag": "work"])
  let reopened = try ProductStore(path: path)
  #expect(try reopened.record(id: record.id)?.metadata["favorite"] == "true")
  _ = try reopened.undo(recordID: record.id)
  #expect(try reopened.record(id: record.id)?.metadata.isEmpty == true)
  _ = try reopened.redo(recordID: record.id)
  #expect(try reopened.record(id: record.id)?.metadata["tag"] == "work")
}

@Test
func productStorePersistsAssetMetadataAlongsideTheDocumentStore() throws {
  let path = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-product-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("library.sqlite").path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let store = try ProductStore(path: path)
  let asset = Asset(
    id: UUID(), contentHash: "abc123", byteCount: 42,
    mediaType: "public.png", originalFilename: "photo.png")
  try store.saveAsset(asset)
  #expect(try store.asset(id: asset.id) == asset)
  #expect(try store.assets() == [asset])
  let reopened = try ProductStore(path: path)
  #expect(try reopened.asset(id: asset.id) == asset)
}

@Test
func productStoreCommitsAssetPlacementAtomicallyAndKeepsAssetForHistory() throws {
  let path = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-product-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("library.sqlite").path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let store = try ProductStore(path: path)
  let recordID = UUID()
  let blockID = UUID()
  let asset = Asset(
    id: UUID(), contentHash: String(repeating: "a", count: 64), byteCount: 4,
    mediaType: "public.image", originalFilename: "photo.png")
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(
      id: blockID, recordID: recordID, position: 0, text: "", type: .image,
      content: .assets([AssetPlacement(assetID: asset.id)]))
  ])
  _ = try store.save(
    record: Record(id: recordID, title: "媒体"),
    document: try BlockDocument(recordID: recordID),
    expectedRevision: 0)
  let operationID = UUID()
  let receipt = try store.save(
    asset: asset,
    record: Record(id: recordID, title: "媒体"),
    document: document,
    expectedRevision: 1,
    operationID: operationID)
  #expect(try store.save(
    asset: asset,
    record: Record(id: recordID, title: "媒体"),
    document: document,
    expectedRevision: 1,
    operationID: operationID) == receipt)
  #expect(try store.asset(id: asset.id) == asset)
  #expect(try store.document(recordID: recordID) == document)
  #expect(try store.operationCount() == 2)

  _ = try store.undo(recordID: recordID)
  #expect(try store.document(recordID: recordID).blocks.isEmpty)
  #expect(try store.asset(id: asset.id) == asset)
  #expect(throws: ProductStoreError.assetConflict) {
    try store.saveAsset(Asset(
      id: asset.id, contentHash: String(repeating: "b", count: 64), byteCount: 4))
  }
  #expect(throws: ProductStoreError.invalidDocument) {
    try store.save(
      asset: asset,
      record: Record(id: recordID, title: "媒体"),
      document: try BlockDocument(recordID: recordID, blocks: [
        Block(id: blockID, recordID: recordID, position: 0, text: "", type: .image)
      ]),
      expectedRevision: 2)
  }
}

@Test
func autosaveFlushPersistsPendingChangeAndClearsIt() async throws {
  let path = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-autosave-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("library.sqlite").path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let store = try ProductStore(path: path)
  let recordID = UUID()
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(id: UUID(), recordID: recordID, position: 0, text: "本地草稿")
  ])
  let autosave = AutosaveCoordinator(store: store)
  let result = await autosave.saveNow(
    record: Record(id: recordID, title: "草稿"),
    document: document,
    expectedRevision: 0,
    operationID: UUID())
  guard case .saved(let receipt) = result else {
    Issue.record("expected autosave to save, got \(result)")
    return
  }
  #expect(receipt.revision == 1)
  #expect(await autosave.pendingRecordIDs().isEmpty)
  #expect(try store.record(id: recordID)?.title == "草稿")
  #expect(try store.document(recordID: recordID) == document)
}

@Test
func autosaveConflictKeepsLocalDraftAndExposesSavedVersion() async throws {
  let path = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-autosave-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("library.sqlite").path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let store = try ProductStore(path: path)
  let recordID = UUID()
  let savedDocument = try BlockDocument(recordID: recordID, blocks: [
    Block(id: UUID(), recordID: recordID, position: 0, text: "已保存")
  ])
  _ = try store.save(
    record: Record(id: recordID, title: "已保存"),
    document: savedDocument,
    expectedRevision: 0)
  let localDocument = try BlockDocument(recordID: recordID, blocks: [
    Block(id: UUID(), recordID: recordID, position: 0, text: "本地未提交")
  ])
  let autosave = AutosaveCoordinator(store: store)
  let result = await autosave.saveNow(
    record: Record(id: recordID, title: "本地未提交"),
    document: localDocument,
    expectedRevision: 0)
  guard case .conflict(let conflict) = result else {
    Issue.record("expected revision conflict, got \(result)")
    return
  }
  #expect(conflict.expectedRevision == 0)
  #expect(conflict.actualRevision == 1)
  #expect(conflict.localRecord.title == "本地未提交")
  #expect(conflict.savedRecord?.title == "已保存")
  #expect(conflict.savedDocument == savedDocument)
  #expect(await autosave.pendingRecordIDs() == [recordID])
  await autosave.cancel(recordID: recordID)
}

@Test
func autosaveScheduleCanBeCancelledBeforeFlush() async throws {
  let path = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-autosave-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("library.sqlite").path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let store = try ProductStore(path: path)
  let recordID = UUID()
  let autosave = AutosaveCoordinator(store: store)
  await autosave.schedule(
    record: Record(id: recordID, title: "取消"),
    document: try BlockDocument(recordID: recordID),
    expectedRevision: 0,
    delayNanoseconds: 1_000_000_000)
  await autosave.cancel(recordID: recordID)
  #expect(await autosave.flush().isEmpty)
  #expect(try store.record(id: recordID) == nil)
}
