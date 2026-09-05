import Foundation
import SynoraDomain
import SynoraStoreProbe

// Writes record+block operations in separate transactions forever so the kill/reopen
// probe can terminate the process at arbitrary transaction boundaries.
guard CommandLine.arguments.count >= 2 else {
  FileHandle.standardError.write("usage: SynoraStoreCrashWriter <db-path>\n".data(using: .utf8)!)
  exit(2)
}

let store = try StoreProbe(path: CommandLine.arguments[1])
let recordID = UUID(uuidString: "00000000-0000-4000-8000-00000000c0de")!
let blockID = UUID(uuidString: "00000000-0000-4000-8000-00000000beef")!
var revision = 0
var blockRevision = 0
while true {
  try store.save(Record(id: recordID, title: "generation \(revision)", revision: revision))
  try store.saveBlock(
    Block(
      id: blockID, recordID: recordID, position: revision, text: "块 \(revision)",
      revision: blockRevision))
  revision += 1
  blockRevision += 1
}
