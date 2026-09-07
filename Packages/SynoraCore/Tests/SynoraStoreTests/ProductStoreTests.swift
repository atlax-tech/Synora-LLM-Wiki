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
