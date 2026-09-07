import Foundation
import SynoraDomain
import SynoraStore

@main
struct SynoraP2Recovery {
  static func main() {
    do {
      let arguments = Array(CommandLine.arguments.dropFirst())
      guard let path = arguments.first else {
        throw CocoaError(.fileReadInvalidFileName)
      }
      if arguments.dropFirst().contains("--check") {
        try check(path: path)
      } else {
        try write(path: path)
      }
    } catch {
      fputs("P2 recovery failed: \(error)\n", stderr)
      exit(1)
    }
  }

  private static func write(path: String) throws {
    let store = try ProductStore(path: path)
    let recordID = UUID(uuidString: "00000000-0000-4000-8000-00000000a202")!
    let blockID = UUID(uuidString: "00000000-0000-4000-8000-00000000b202") ?? UUID()
    var revision = try store.record(id: recordID)?.revision ?? 0
    var document: BlockDocument
    if try store.record(id: recordID) != nil {
      document = try store.document(recordID: recordID)
    } else {
      document = try BlockDocument(
        recordID: recordID,
        blocks: [Block(id: blockID, recordID: recordID, position: 0, text: "")])
    }
    for index in 0..<10_000 {
      document = try document.editing(id: blockID, text: "confirmed-\(index)")
      let receipt = try store.save(
        record: Record(id: recordID, title: "Recovery", revision: revision),
        document: document,
        expectedRevision: revision)
      revision = receipt.revision
      if index.isMultiple(of: 5) { Thread.sleep(forTimeInterval: 0.002) }
    }
  }

  private static func check(path: String) throws {
    let store = try ProductStore(path: path)
    try store.verifyIntegrity()
    let record = try store.records().first
    let document = try record.map { try store.document(recordID: $0.id) }
    guard try store.operationCount() > 0, let record, let document, !document.blocks.isEmpty
    else { throw CocoaError(.fileReadCorruptFile) }
    print("P2_RECOVERY_CHECK=PASS operations=\(try store.operationCount()) revision=\(record.revision)")
  }
}
