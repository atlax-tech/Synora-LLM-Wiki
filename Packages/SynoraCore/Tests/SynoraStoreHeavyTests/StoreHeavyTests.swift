import Foundation
import GRDB
import SynoraDomain
import Testing

@testable import SynoraStoreProbe

// SplitMix64 gives the 100k corpus a fixed, reproducible operation sequence.
struct SeededRandom {
  private var state: UInt64
  init(seed: UInt64) {
    state = seed
  }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

func deterministicUUID(_ value: UInt64) -> UUID {
  var bytes = [UInt8](repeating: 0, count: 16)
  bytes[6] = 0x40
  withUnsafeBytes(of: value.bigEndian) { raw in
    bytes[8] = (raw[raw.startIndex] & 0x3F) | 0x80
    bytes.replaceSubrange(9..<16, with: raw.dropFirst())
  }
  return UUID(
    uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14],
      bytes[15]
    ))
}

// Runs in the heavy suite via `script/p0.sh store`: the full sweep takes minutes of
// fsync-per-transaction work and the disk-full case needs hdiutil.
@Test
func seeded100kMixedOperationsConvergeAcrossReplayAndSnapshotRecovery() throws {
  let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let store = try StoreProbe(path: path)
  var random = SeededRandom(seed: 20_260_905)
  let recordCount = 10_000
  var records: [UUID] = []
  var recordRevisions: [UUID: Int] = [:]
  var aliveBlocks: [(id: UUID, recordIndex: Int, revision: Int)] = []
  records.reserveCapacity(recordCount)
  for index in 0..<recordCount {
    let id = deterministicUUID(UInt64(index &+ 1))
    try store.save(Record(id: id, title: "记录 \(index) 👩‍💻", revision: 0))
    records.append(id)
    recordRevisions[id] = 1
  }
  var assetCount = 0
  let mixedOperations = 90_000
  for _ in 0..<mixedOperations {
    let draw = random.next()
    let recordIndex = Int(truncatingIfNeeded: draw >> 8) % records.count
    switch draw % 100 {
    case 0..<40:
      let id = records[recordIndex]
      let revision = recordRevisions[id]!
      try store.save(Record(id: id, title: "更新 \(draw)", revision: revision))
      recordRevisions[id] = revision + 1
    case 40..<65:
      let id = deterministicUUID(draw)
      try store.saveBlock(
        Block(id: id, recordID: records[recordIndex], position: 0, text: "块 \(draw)"))
      aliveBlocks.append((id, recordIndex, 1))
    case 65..<80:
      guard !aliveBlocks.isEmpty else {
        try store.importAsset(
          Asset(id: deterministicUUID(draw), contentHash: "\(draw)", byteCount: Int64(draw % 4096)))
        assetCount += 1
        continue
      }
      let index = Int(truncatingIfNeeded: draw >> 8) % aliveBlocks.count
      var block = aliveBlocks[index]
      try store.saveBlock(
        Block(
          id: block.id, recordID: records[recordIndex], position: Int(truncatingIfNeeded: draw),
          text: "移动 \(draw)", revision: block.revision))
      block.recordIndex = recordIndex
      block.revision += 1
      aliveBlocks[index] = block
    case 80..<90:
      guard !aliveBlocks.isEmpty else {
        try store.importAsset(
          Asset(id: deterministicUUID(draw), contentHash: "\(draw)", byteCount: Int64(draw % 4096)))
        assetCount += 1
        continue
      }
      let index = Int(truncatingIfNeeded: draw >> 8) % aliveBlocks.count
      try store.deleteBlock(id: aliveBlocks[index].id, revision: aliveBlocks[index].revision)
      aliveBlocks.remove(at: index)
    default:
      try store.importAsset(
        Asset(id: deterministicUUID(draw), contentHash: "\(draw)", byteCount: Int64(draw % 4096)))
      assetCount += 1
    }
  }
  #expect(try store.operationCount() == recordCount + mixedOperations)
  let expected = try store.projectionHash()
  try store.replayProjection()
  #expect(try store.projectionHash() == expected)
  _ = try store.snapshot()
  #expect(try store.recoverFromSnapshot() != nil)
  #expect(try store.projectionHash() == expected)
  #expect(
    try store.record(id: records[recordCount - 1])?.revision == recordRevisions[
      records[recordCount - 1]]!)
  if let lastBlock = aliveBlocks.last {
    #expect(try store.block(id: lastBlock.id)?.revision == lastBlock.revision)
  }
  #expect(assetCount > 0)
}

@Test
func replayRejectsSequenceReorderAtomically() throws {
  let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let store = try StoreProbe(path: path)
  let id = UUID()
  for revision in 0..<3 {
    try store.save(Record(id: id, title: "rev \(revision)", revision: revision))
  }
  let before = try store.projectionHash()
  let database = try DatabaseQueue(path: path)
  try database.write { db in
    try db.execute(sql: "UPDATE operations SET sequence = -1 WHERE sequence = 2")
    try db.execute(sql: "UPDATE operations SET sequence = 2 WHERE sequence = 3")
    try db.execute(sql: "UPDATE operations SET sequence = 3 WHERE sequence = -1")
  }
  #expect(throws: StoreError.invalidOperation) { try store.replayProjection() }
  #expect(try store.projectionHash() == before)
}

@Test
func killedWriterLeavesOnlyCompleteTransactionsAfterReopen() throws {
  let binary = Bundle(for: BundleMarker.self).bundleURL
    .deletingLastPathComponent()  // debug
    .appendingPathComponent("SynoraStoreCrashWriter")
  guard FileManager.default.isExecutableFile(atPath: binary.path) else {
    Issue.record("missing crash writer executable at \(binary.path)")
    return
  }
  let blockID = UUID(uuidString: "00000000-0000-4000-8000-00000000beef")!
  for round in 0..<3 {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("kill-\(round)-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: path) }
    let process = Process()
    process.executableURL = binary
    process.arguments = [path]
    try process.run()
    let threshold = 20 + round * 10
    var reader: StoreProbe?
    var operations = 0
    while operations < threshold {
      if !process.isRunning { break }
      if reader == nil, let opened = try? StoreProbe(path: path) {
        reader = opened
      }
      operations = (try? reader?.operationCount()) ?? 0
    }
    kill(process.processIdentifier, SIGKILL)
    process.waitUntilExit()
    guard operations >= threshold else {
      Issue.record("writer exited before reaching \(threshold) operations")
      return
    }
    let store = try StoreProbe(path: path)
    let hashBefore = try store.projectionHash()
    try store.replayProjection()
    #expect(try store.projectionHash() == hashBefore)
    let operationCount = try store.operationCount()
    #expect(operationCount >= threshold)
    // A killed writer may only lose the trailing record+block pair of one generation.
    let block = try store.block(id: blockID)
    #expect(block != nil || operationCount % 2 == 1)
  }
}

private final class BundleMarker {}

@Test
func constrainedVolumeReportsDiskFullAndKeepsLastCommitRecoverable() throws {
  let image = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-full-\(UUID().uuidString).dmg").path
  defer { try? FileManager.default.removeItem(atPath: image) }
  let create = ShellProcess(
    "/usr/bin/hdiutil",
    ["create", "-size", "6m", "-fs", "APFS", "-volname", "SynoraP0Full", image])
  let attach = ShellProcess("/usr/bin/hdiutil", ["attach", image, "-nobrowse", "-quiet"])
  #expect(create.status == 0 && attach.status == 0)
  guard create.status == 0 && attach.status == 0 else { return }
  let mountPoint = "/Volumes/SynoraP0Full"
  defer { _ = ShellProcess("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet"]) }
  let path = URL(fileURLWithPath: mountPoint).appendingPathComponent("store.sqlite").path
  let store = try StoreProbe(path: path)
  let id = UUID()
  var hitDiskFull = false
  var committed = 0
  for revision in 0..<200_000 {
    do {
      try store.save(Record(id: id, title: "row \(revision)", revision: revision))
      committed = revision + 1
    } catch let error as DatabaseError where error.resultCode == .SQLITE_FULL {
      hitDiskFull = true
      break
    }
  }
  #expect(hitDiskFull)
  #expect(committed > 0)
  // The full volume may not have room to rewrite the projection, so recovery is verified
  // on a byte-identical copy moved off the constrained volume.
  let recovery = FileManager.default.temporaryDirectory
    .appendingPathComponent("recovery-\(UUID().uuidString)").path
  defer { try? FileManager.default.removeItem(atPath: recovery) }
  try FileManager.default.createDirectory(atPath: recovery, withIntermediateDirectories: true)
  for suffix in ["", "-wal", "-shm"] {
    let source = URL(fileURLWithPath: path + suffix)
    guard FileManager.default.fileExists(atPath: source.path) else { continue }
    try FileManager.default.copyItem(
      at: source, to: URL(fileURLWithPath: recovery + "/store.sqlite" + suffix))
  }
  let reopened = try StoreProbe(path: recovery + "/store.sqlite")
  #expect(try reopened.record(id: id)?.revision == committed)
  let hashBefore = try reopened.projectionHash()
  try reopened.replayProjection()
  #expect(try reopened.projectionHash() == hashBefore)
}

struct ShellProcess {
  let status: Int32
  init(_ path: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      process.waitUntilExit()
      status = process.terminationStatus
    } catch {
      status = -1
    }
  }
}
