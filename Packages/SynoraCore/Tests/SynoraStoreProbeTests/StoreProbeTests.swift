import Foundation
import GRDB
import SynoraDomain
import Testing

@testable import SynoraStoreProbe

@Test
func storeWritesOperationAndRejectsStaleRevisionWithoutPartialWrite() throws {
  let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let id = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
  let secondOperationID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
  let store = try StoreProbe(path: path, ids: FixedIDGenerator([id, secondOperationID]))
  let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
  let first = try store.saveReceipt(Record(id: recordID, title: "first"))
  #expect(first.revision == 1)
  #expect(try store.operationCount() == 1)
  let repeated =
    try store.saveReceipt(
      Record(id: recordID, title: "first"), operationID: first.operationID)
  #expect(repeated == first)
  #expect(try store.operationCount() == 1)
  #expect(try store.record(id: recordID)?.title == "first")
  #expect(throws: StoreError.operationConflict) {
    try store.saveReceipt(
      Record(id: recordID, title: "different"), operationID: first.operationID)
  }
  #expect(throws: RevisionError.stale(expected: 0, actual: 1)) {
    try store.saveReceipt(Record(id: recordID, title: "stale", revision: 0))
  }
  #expect(try store.operationCount() == 1)
  #expect(try store.record(id: recordID)?.title == "first")
  let snapshot = try store.snapshot()
  #expect(snapshot.isValid())
  #expect(try store.latestSnapshot() == snapshot)
}

@Test
func replayRestoresProjectionAndRejectsCorruptLogAtomically() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let path = directory.appendingPathComponent("store.sqlite").path
  let store = try StoreProbe(path: path)
  let id = UUID()
  for revision in 0..<100 {
    try store.save(Record(id: id, title: "版本 \(revision) 👩‍💻", revision: revision))
  }
  let expected = try store.record(id: id)
  let oldSnapshot = try store.snapshot()
  try store.save(Record(id: id, title: "latest", revision: 100))
  let newSnapshot = try store.snapshot()
  let database = try DatabaseQueue(path: path)
  try database.write { db in
    try db.execute(
      sql: "UPDATE snapshots SET sha256 = 'damaged' WHERE up_to_sequence = ?",
      arguments: [newSnapshot.upToSequence])
  }
  #expect(try store.latestSnapshot() == oldSnapshot)
  let latest = try store.record(id: id)
  try database.write { db in try db.execute(sql: "DELETE FROM records") }
  try store.replayProjection()
  #expect(try store.record(id: id) == latest)
  #expect(expected?.revision == 100)
  #expect(try store.operationCount() == 101)
  try database.write { db in
    try db.execute(sql: "UPDATE operations SET hash = 'damaged' WHERE sequence = 50")
  }
  #expect(throws: StoreError.invalidOperation) { try store.replayProjection() }
  #expect(try store.record(id: id) == latest)
}

@Test
func blockAndAssetProjectionRoundTripsThroughReplayAndRecovery() throws {
  let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let store = try StoreProbe(path: path)
  let recordID = UUID()
  // The sentinel flows through the store like real user content; the quality gate
  // asserts it never surfaces in logs, build artifacts or release bundles.
  try store.save(
    Record(id: recordID, title: "宿主记录 SYNORA-SENTINEL-CONTENT-20260905", revision: 0))
  let blockID = UUID()
  try store.saveBlock(Block(id: blockID, recordID: recordID, position: 0, text: "首块"))
  #expect(try store.block(id: blockID)?.revision == 1)
  try store.saveBlock(Block(id: blockID, recordID: recordID, position: 1, text: "移动", revision: 1))
  #expect(try store.block(id: blockID)?.position == 1)
  let assetID = UUID()
  try store.importAsset(Asset(id: assetID, contentHash: "abc", byteCount: 3))
  #expect(try store.importAsset(Asset(id: assetID, contentHash: "abc", byteCount: 3)) != nil)
  #expect(throws: StoreError.operationConflict) {
    try store.importAsset(Asset(id: assetID, contentHash: "different", byteCount: 9))
  }
  #expect(throws: StoreError.missingRecord) {
    try store.saveBlock(Block(id: UUID(), recordID: UUID(), position: 0, text: "孤儿"))
  }
  let expected = try store.projectionHash()
  try store.replayProjection()
  #expect(try store.projectionHash() == expected)
  _ = try store.snapshot()
  #expect(try store.recoverFromSnapshot() != nil)
  #expect(try store.projectionHash() == expected)
  try store.deleteBlock(id: blockID, revision: 2)
  #expect(try store.block(id: blockID) == nil)
}
