import Foundation
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
      Record(id: recordID, title: "ignored"), operationID: first.operationID)
  #expect(repeated == first)
  #expect(try store.operationCount() == 1)
  #expect(try store.record(id: recordID)?.title == "first")
  #expect(throws: RevisionError.stale(expected: 0, actual: 1)) {
    try store.saveReceipt(Record(id: recordID, title: "stale", revision: 0))
  }
  #expect(try store.operationCount() == 1)
  #expect(try store.record(id: recordID)?.title == "first")
  let snapshot = try store.snapshot()
  #expect(snapshot.isValid())
  #expect(try store.latestSnapshot() == snapshot)
}
