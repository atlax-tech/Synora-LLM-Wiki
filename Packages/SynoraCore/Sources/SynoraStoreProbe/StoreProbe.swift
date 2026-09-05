import CryptoKit
import Foundation
import GRDB
import SynoraDomain

public struct StoreReceipt: Hashable, Sendable {
  public let operationID: UUID
  public let sequence: Int64
  public let revision: Int

  public init(operationID: UUID, sequence: Int64, revision: Int) {
    self.operationID = operationID
    self.sequence = sequence
    self.revision = revision
  }
}

public enum StoreError: Error, Equatable, Sendable {
  case missingRecord
  case invalidRecord
  case invalidSnapshot
  case operationConflict
  case invalidOperation
}

public final class StoreProbe: RecordRepository, @unchecked Sendable {
  private let pool: DatabasePool
  private let clock: any Clock
  private let ids: any IDGenerator

  public init(
    path: String,
    clock: any Clock = SystemClock(),
    ids: any IDGenerator = UUIDGenerator()
  ) throws {
    self.pool = try DatabasePool(path: path)
    self.clock = clock
    self.ids = ids
    try migrate()
  }

  public func migrate() throws {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("p0") { db in
      try db.execute(
        sql: """
          CREATE TABLE IF NOT EXISTS records (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            revision INTEGER NOT NULL
          );
          CREATE TABLE IF NOT EXISTS operations (
            id TEXT PRIMARY KEY NOT NULL,
            transaction_id INTEGER NOT NULL,
            sequence INTEGER NOT NULL UNIQUE,
            entity_id TEXT NOT NULL,
            entity_revision INTEGER NOT NULL,
            kind TEXT NOT NULL,
            payload BLOB NOT NULL,
            timestamp REAL NOT NULL,
            previous_hash TEXT,
            hash TEXT NOT NULL,
            request_hash TEXT NOT NULL DEFAULT ''
          );
          CREATE TABLE IF NOT EXISTS blocks (
            id TEXT PRIMARY KEY NOT NULL,
            record_id TEXT NOT NULL,
            position INTEGER NOT NULL,
            text TEXT NOT NULL,
            revision INTEGER NOT NULL
          );
          CREATE TABLE IF NOT EXISTS assets (
            id TEXT PRIMARY KEY NOT NULL,
            content_hash TEXT NOT NULL,
            byte_count INTEGER NOT NULL
          );
          CREATE TABLE IF NOT EXISTS snapshots (
            up_to_sequence INTEGER PRIMARY KEY NOT NULL,
            normalized_state BLOB NOT NULL,
            sha256 TEXT NOT NULL
          );
          CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
          );
          PRAGMA journal_mode = WAL;
          """)
    }
    migrator.registerMigration("p0-replay-fingerprint") { db in
      let operationColumns = try db.columns(in: "operations")
      if !operationColumns.contains(where: { $0.name == "request_hash" }) {
        try db.execute(
          sql: "ALTER TABLE operations ADD COLUMN request_hash TEXT NOT NULL DEFAULT ''")
      }
      try db.execute(
        sql: """
          CREATE TABLE IF NOT EXISTS blocks (
            id TEXT PRIMARY KEY NOT NULL,
            record_id TEXT NOT NULL,
            position INTEGER NOT NULL,
            text TEXT NOT NULL,
            revision INTEGER NOT NULL
          );
          CREATE TABLE IF NOT EXISTS assets (
            id TEXT PRIMARY KEY NOT NULL,
            content_hash TEXT NOT NULL,
            byte_count INTEGER NOT NULL
          );
          """)
    }
    try migrator.migrate(pool)
  }

  public func record(id: UUID) throws -> SynoraDomain.Record? {
    try pool.read { db in
      guard
        let row = try Row.fetchOne(
          db, sql: "SELECT id, title, revision FROM records WHERE id = ?",
          arguments: [id.uuidString])
      else {
        return nil
      }
      guard
        let storedID: String = row["id"],
        let recordID = UUID(uuidString: storedID),
        let title: String = row["title"],
        let revision: Int = row["revision"]
      else {
        throw StoreError.invalidRecord
      }
      return SynoraDomain.Record(
        id: recordID,
        title: title,
        revision: revision
      )
    }
  }

  public func save(_ record: SynoraDomain.Record) throws {
    _ = try saveReceipt(record)
  }

  @discardableResult
  public func saveReceipt(_ record: SynoraDomain.Record, operationID: UUID? = nil) throws
    -> StoreReceipt
  {
    let operationID = operationID ?? ids.next()
    let fingerprint = requestHash(for: record)
    return try pool.write { db in
      if let existing = try Row.fetchOne(
        db,
        sql:
          "SELECT sequence, entity_revision, entity_id, kind, payload, request_hash FROM operations WHERE id = ?",
        arguments: [operationID.uuidString])
      {
        guard let storedRequestHash: String = existing["request_hash"],
          storedRequestHash == fingerprint
        else {
          throw StoreError.operationConflict
        }
        guard let sequence: Int64 = existing["sequence"],
          let revision: Int = existing["entity_revision"]
        else {
          throw StoreError.invalidRecord
        }
        return StoreReceipt(
          operationID: operationID, sequence: sequence, revision: revision)
      }

      let currentRevision: Int =
        try Row.fetchOne(
          db,
          sql: "SELECT revision FROM records WHERE id = ?",
          arguments: [record.id.uuidString]
        )?["revision"] ?? 0
      guard record.revision == currentRevision else {
        throw RevisionError.stale(expected: record.revision, actual: currentRevision)
      }

      let nextRevision = record.revision + 1
      let persistedRecord = SynoraDomain.Record(
        id: record.id, title: record.title, revision: nextRevision)
      return try Self.appendOperation(
        db, operationID: operationID, entityID: record.id, entityRevision: nextRevision,
        kind: "record.save", payload: Self.canonicalPayload(persistedRecord), clock: clock,
        fingerprint: fingerprint
      ) { receipt in
        try db.execute(
          sql:
            "INSERT INTO records (id, title, revision) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET title = excluded.title, revision = excluded.revision",
          arguments: [record.id.uuidString, record.title, nextRevision]
        )
        return receipt
      }
    }
  }

  public func block(id: UUID) throws -> Block? {
    try pool.read { db in
      try Self.decodeBlock(
        Row.fetchOne(db, sql: "SELECT * FROM blocks WHERE id = ?", arguments: [id.uuidString]))
    }
  }

  @discardableResult
  public func saveBlock(_ block: Block, operationID: UUID? = nil) throws -> StoreReceipt {
    let operationID = operationID ?? ids.next()
    let fingerprint = requestHash(for: block)
    return try pool.write { db in
      if let existing = try Row.fetchOne(
        db, sql: "SELECT sequence, entity_revision FROM operations WHERE id = ?",
        arguments: [operationID.uuidString])
      {
        return try Self.replayedReceipt(
          existing, operationID: operationID, fingerprint: fingerprint)
      }
      guard
        try Row.fetchOne(
          db, sql: "SELECT id FROM records WHERE id = ?",
          arguments: [block.recordID.uuidString]) != nil
      else {
        throw StoreError.missingRecord
      }
      let currentRevision: Int =
        try Row.fetchOne(
          db, sql: "SELECT revision FROM blocks WHERE id = ?", arguments: [block.id.uuidString]
        )?["revision"] ?? 0
      guard block.revision == currentRevision else {
        throw RevisionError.stale(expected: block.revision, actual: currentRevision)
      }
      let persisted = Block(
        id: block.id, recordID: block.recordID, position: block.position, text: block.text,
        revision: currentRevision + 1)
      return try Self.appendOperation(
        db, operationID: operationID, entityID: block.id, entityRevision: persisted.revision,
        kind: "block.save", payload: Self.canonicalPayload(persisted), clock: clock,
        fingerprint: fingerprint
      ) { receipt in
        try db.execute(
          sql:
            "INSERT INTO blocks (id, record_id, position, text, revision) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET record_id = excluded.record_id, position = excluded.position, text = excluded.text, revision = excluded.revision",
          arguments: [
            persisted.id.uuidString, persisted.recordID.uuidString, persisted.position,
            persisted.text, persisted.revision,
          ])
        return receipt
      }
    }
  }

  @discardableResult
  public func deleteBlock(id: UUID, revision: Int, operationID: UUID? = nil) throws -> StoreReceipt
  {
    let operationID = operationID ?? ids.next()
    let payload = Self.canonicalPayload(BlockDeleteRequest(id: id, revision: revision))
    let fingerprint = Self.fingerprint(of: payload)
    return try pool.write { db in
      if let existing = try Row.fetchOne(
        db, sql: "SELECT sequence, entity_revision FROM operations WHERE id = ?",
        arguments: [operationID.uuidString])
      {
        return try Self.replayedReceipt(
          existing, operationID: operationID, fingerprint: fingerprint)
      }
      let currentRevision: Int =
        try Row.fetchOne(
          db, sql: "SELECT revision FROM blocks WHERE id = ?", arguments: [id.uuidString]
        )?["revision"] ?? -1
      guard currentRevision >= 0 else {
        throw StoreError.missingRecord
      }
      guard revision == currentRevision else {
        throw RevisionError.stale(expected: revision, actual: currentRevision)
      }
      return try Self.appendOperation(
        db, operationID: operationID, entityID: id, entityRevision: revision,
        kind: "block.delete", payload: payload, clock: clock, fingerprint: fingerprint
      ) { receipt in
        try db.execute(sql: "DELETE FROM blocks WHERE id = ?", arguments: [id.uuidString])
        return receipt
      }
    }
  }

  @discardableResult
  public func importAsset(_ asset: Asset, operationID: UUID? = nil) throws -> StoreReceipt {
    let operationID = operationID ?? ids.next()
    let fingerprint = requestHash(for: asset)
    return try pool.write { db in
      if let existing = try Row.fetchOne(
        db, sql: "SELECT sequence, entity_revision FROM operations WHERE id = ?",
        arguments: [operationID.uuidString])
      {
        return try Self.replayedReceipt(
          existing, operationID: operationID, fingerprint: fingerprint)
      }
      // Asset ids are content-addressed: the same id may never change content.
      if let existing = try Row.fetchOne(
        db, sql: "SELECT content_hash, byte_count FROM assets WHERE id = ?",
        arguments: [asset.id.uuidString])
      {
        let storedHash: String = existing["content_hash"]
        let storedBytes: Int64 = existing["byte_count"]
        guard storedHash == asset.contentHash, storedBytes == asset.byteCount else {
          throw StoreError.operationConflict
        }
      }
      return try Self.appendOperation(
        db, operationID: operationID, entityID: asset.id, entityRevision: 0,
        kind: "asset.import", payload: Self.canonicalPayload(asset), clock: clock,
        fingerprint: fingerprint
      ) { receipt in
        try db.execute(
          sql:
            "INSERT INTO assets (id, content_hash, byte_count) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET content_hash = excluded.content_hash, byte_count = excluded.byte_count",
          arguments: [asset.id.uuidString, asset.contentHash, asset.byteCount])
        return receipt
      }
    }
  }

  public func operationCount() throws -> Int {
    try pool.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM operations") ?? 0
    }
  }

  public func snapshot() throws -> Snapshot {
    try pool.write { db in
      let state = try Self.readProjection(db)
      let normalized = Self.normalizedState(from: state)
      let sequence =
        try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(sequence), 0) FROM operations") ?? 0
      let snapshot = Snapshot(upToSequence: sequence, normalizedState: normalized)
      try db.execute(
        sql:
          "INSERT OR REPLACE INTO snapshots (up_to_sequence, normalized_state, sha256) VALUES (?, ?, ?)",
        arguments: [snapshot.upToSequence, snapshot.normalizedState, snapshot.sha256]
      )
      return snapshot
    }
  }

  public func latestSnapshot() throws -> Snapshot? {
    try pool.read { db in
      let rows = try Row.fetchAll(
        db,
        sql:
          "SELECT up_to_sequence, normalized_state, sha256 FROM snapshots ORDER BY up_to_sequence DESC"
      )
      guard !rows.isEmpty else {
        return nil
      }
      let latestSequence =
        try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(sequence), 0) FROM operations") ?? 0
      var foundInvalidSnapshot = false
      for row in rows {
        guard let sequence: Int64 = row["up_to_sequence"],
          let normalizedState: Data = row["normalized_state"],
          let storedHash: String = row["sha256"],
          sequence <= latestSequence
        else {
          foundInvalidSnapshot = true
          continue
        }
        let snapshot = Snapshot(upToSequence: sequence, normalizedState: normalizedState)
        if snapshot.sha256 == storedHash {
          return snapshot
        }
        foundInvalidSnapshot = true
      }
      if foundInvalidSnapshot {
        throw StoreError.invalidSnapshot
      }
      return nil
    }
  }

  /// Restores the newest valid snapshot and replays operations after it. Falls back to a full
  /// replay when no snapshot exists, so recovery never skips an operation.
  @discardableResult
  public func recoverFromSnapshot() throws -> Snapshot? {
    let snapshot = try latestSnapshot()
    try pool.write { db in
      let state: ReplayState
      if let snapshot {
        guard let restored = ReplayState(snapshotState: snapshot.normalizedState) else {
          throw StoreError.invalidSnapshot
        }
        state = restored
      } else {
        state = ReplayState()
      }
      var replayed = state
      let afterSequence = snapshot?.upToSequence ?? 0
      var sequence = afterSequence
      var previousHash: String? = try String.fetchOne(
        db, sql: "SELECT hash FROM operations WHERE sequence = ?", arguments: [afterSequence])
      if afterSequence == 0 {
        previousHash = nil
      }
      let cursor = try Row.fetchCursor(
        db, sql: "SELECT * FROM operations WHERE sequence > ? ORDER BY sequence",
        arguments: [afterSequence])
      while let row = try cursor.next() {
        let operation = try Self.decodeOperation(row, expectedSequence: sequence + 1)
        guard operation.previousHash == previousHash, operation.hash == row["hash"] else {
          throw StoreError.invalidOperation
        }
        try Self.apply(operation, to: &replayed)
        sequence = operation.sequence
        previousHash = operation.hash
      }
      try Self.writeProjection(replayed, db: db)
    }
    return snapshot
  }

  public func projectionHash() throws -> String {
    let snapshot = try snapshot()
    return snapshot.sha256
  }

  /// Rebuilds the full projection only after validating the complete operation chain.
  public func replayProjection() throws {
    try pool.write { db in
      var state = ReplayState()
      var sequence: Int64 = 0
      var previousHash: String?
      let cursor = try Row.fetchCursor(db, sql: "SELECT * FROM operations ORDER BY sequence")
      while let row = try cursor.next() {
        let operation = try Self.decodeOperation(row, expectedSequence: sequence + 1)
        guard operation.previousHash == previousHash, operation.hash == row["hash"] else {
          throw StoreError.invalidOperation
        }
        try Self.apply(operation, to: &state)
        sequence = operation.sequence
        previousHash = operation.hash
      }
      try Self.writeProjection(state, db: db)
    }
  }

  private func requestHash(for record: SynoraDomain.Record) -> String {
    Self.fingerprint(of: Self.canonicalPayload(record))
  }

  private func requestHash(for block: Block) -> String {
    Self.fingerprint(of: Self.canonicalPayload(block))
  }

  private func requestHash(for asset: Asset) -> String {
    Self.fingerprint(of: Self.canonicalPayload(asset))
  }

  // MARK: - Operation append helpers

  private static func canonicalPayload<T: Codable>(_ value: T) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(value)) ?? Data()
  }

  private static func canonicalPayload(_ dictionary: [String: String]) -> Data {
    (try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])) ?? Data()
  }

  private static func fingerprint(of data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func replayedReceipt(
    _ row: Row, operationID: UUID, fingerprint: String
  ) throws -> StoreReceipt {
    guard let storedFingerprint: String = row["request_hash"], storedFingerprint == fingerprint,
      let sequence: Int64 = row["sequence"], let revision: Int = row["entity_revision"]
    else {
      throw StoreError.operationConflict
    }
    return StoreReceipt(operationID: operationID, sequence: sequence, revision: revision)
  }

  /// Appends one canonical operation and applies the projection mutation inside the caller's
  /// write transaction. The receipt is returned only after the mutation succeeds.
  private static func appendOperation(
    _ db: Database,
    operationID: UUID,
    entityID: UUID,
    entityRevision: Int,
    kind: String,
    payload: Data,
    clock: any Clock,
    fingerprint: String,
    mutate: (StoreReceipt) throws -> StoreReceipt
  ) throws -> StoreReceipt {
    let sequence =
      (try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(sequence), 0) + 1 FROM operations")) ?? 1
    let transactionID =
      (try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(transaction_id), 0) + 1 FROM operations"))
      ?? 1
    let previousHash = try String.fetchOne(
      db, sql: "SELECT hash FROM operations ORDER BY sequence DESC LIMIT 1")
    let operation = SynoraDomain.Operation(
      id: operationID,
      transactionID: transactionID,
      sequence: sequence,
      entityID: entityID,
      entityRevision: entityRevision,
      kind: kind,
      payload: payload,
      timestamp: clock.now(),
      previousHash: previousHash
    )
    try db.execute(
      sql: """
        INSERT INTO operations
          (id, transaction_id, sequence, entity_id, entity_revision, kind, payload, timestamp, previous_hash, hash, request_hash)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
      arguments: [
        operation.id.uuidString,
        operation.transactionID,
        operation.sequence,
        operation.entityID.uuidString,
        operation.entityRevision,
        operation.kind,
        operation.payload,
        operation.timestamp.timeIntervalSince1970,
        operation.previousHash,
        operation.hash,
        fingerprint,
      ]
    )
    return try mutate(
      StoreReceipt(operationID: operationID, sequence: sequence, revision: entityRevision))
  }

  // MARK: - Replay state machine

  private struct ReplayState {
    var records: [UUID: SynoraDomain.Record] = [:]
    var blocks: [UUID: Block] = [:]
    var assets: [UUID: Asset] = [:]

    init() {}

    init?(snapshotState: Data) {
      guard
        let dictionary = try? JSONSerialization.jsonObject(with: snapshotState) as? [String: Any],
        let recordDictionaries = dictionary["records"] as? [[String: Any]],
        let blockDictionaries = dictionary["blocks"] as? [[String: Any]],
        let assetDictionaries = dictionary["assets"] as? [[String: Any]]
      else {
        return nil
      }
      for entry in recordDictionaries {
        guard let record = Self.decodeRecord(entry) else { return nil }
        records[record.id] = record
      }
      for entry in blockDictionaries {
        guard let block = Self.decodeBlock(entry) else { return nil }
        blocks[block.id] = block
      }
      for entry in assetDictionaries {
        guard let asset = Self.decodeAsset(entry) else { return nil }
        assets[asset.id] = asset
      }
    }

    private static func decodeRecord(_ entry: [String: Any]) -> SynoraDomain.Record? {
      guard let idText = entry["id"] as? String, let id = UUID(uuidString: idText),
        let title = entry["title"] as? String, let revision = entry["revision"] as? Int
      else {
        return nil
      }
      return SynoraDomain.Record(id: id, title: title, revision: revision)
    }

    private static func decodeBlock(_ entry: [String: Any]) -> Block? {
      guard let idText = entry["id"] as? String, let id = UUID(uuidString: idText),
        let recordText = entry["recordID"] as? String, let recordID = UUID(uuidString: recordText),
        let position = entry["position"] as? Int, let text = entry["text"] as? String,
        let revision = entry["revision"] as? Int
      else {
        return nil
      }
      return Block(id: id, recordID: recordID, position: position, text: text, revision: revision)
    }

    private static func decodeAsset(_ entry: [String: Any]) -> Asset? {
      guard let idText = entry["id"] as? String, let id = UUID(uuidString: idText),
        let contentHash = entry["contentHash"] as? String,
        let byteCount = entry["byteCount"] as? Int64
      else {
        return nil
      }
      return Asset(id: id, contentHash: contentHash, byteCount: byteCount)
    }
  }

  private static func decodeOperation(_ row: Row, expectedSequence: Int64) throws
    -> SynoraDomain.Operation
  {
    guard let idText: String = row["id"], let id = UUID(uuidString: idText),
      let entityText: String = row["entity_id"], let entityID = UUID(uuidString: entityText),
      let transactionID: Int64 = row["transaction_id"],
      let storedSequence: Int64 = row["sequence"], storedSequence == expectedSequence,
      let revision: Int = row["entity_revision"], revision >= 0,
      let kind: String = row["kind"], Self.validKinds.contains(kind),
      let payload: Data = row["payload"],
      let timestamp: Double = row["timestamp"], timestamp.isFinite
    else {
      throw StoreError.invalidOperation
    }
    return SynoraDomain.Operation(
      id: id, transactionID: transactionID, sequence: storedSequence, entityID: entityID,
      entityRevision: revision, kind: kind, payload: payload,
      timestamp: Date(timeIntervalSince1970: timestamp), previousHash: row["previous_hash"])
  }

  private static let validKinds: Set<String> = [
    "record.save", "block.save", "block.delete", "asset.import",
  ]

  private static func apply(_ operation: SynoraDomain.Operation, to state: inout ReplayState) throws
  {
    let decoder = JSONDecoder()
    switch operation.kind {
    case "record.save":
      guard
        let record = try? decoder.decode(SynoraDomain.Record.self, from: operation.payload),
        record.id == operation.entityID, record.revision == operation.entityRevision,
        operation.entityRevision == (state.records[operation.entityID]?.revision ?? 0) + 1
      else {
        throw StoreError.invalidOperation
      }
      state.records[record.id] = record
    case "block.save":
      guard
        let block = try? decoder.decode(Block.self, from: operation.payload),
        block.id == operation.entityID, block.revision == operation.entityRevision,
        operation.entityRevision == (state.blocks[operation.entityID]?.revision ?? 0) + 1,
        state.records[block.recordID] != nil
      else {
        throw StoreError.invalidOperation
      }
      state.blocks[block.id] = block
    case "block.delete":
      guard
        let request = try? decoder.decode(BlockDeleteRequest.self, from: operation.payload),
        request.id == operation.entityID, request.revision == operation.entityRevision,
        state.blocks[request.id]?.revision == request.revision
      else {
        throw StoreError.invalidOperation
      }
      state.blocks.removeValue(forKey: request.id)
    case "asset.import":
      guard
        let asset = try? decoder.decode(Asset.self, from: operation.payload),
        asset.id == operation.entityID, operation.entityRevision == 0,
        state.assets[asset.id].map({ $0 == asset }) ?? true
      else {
        throw StoreError.invalidOperation
      }
      state.assets[asset.id] = asset
    default:
      throw StoreError.invalidOperation
    }
  }

  private struct BlockDeleteRequest: Codable {
    let id: UUID
    let revision: Int
  }

  // MARK: - Projection persistence

  private static func readProjection(_ db: Database) throws -> ReplayState {
    var state = ReplayState()
    for row in try Row.fetchAll(db, sql: "SELECT id, title, revision FROM records") {
      guard let record = Self.decodeRecordRow(row) else {
        throw StoreError.invalidRecord
      }
      state.records[record.id] = record
    }
    for row in try Row.fetchAll(
      db, sql: "SELECT id, record_id, position, text, revision FROM blocks")
    {
      guard let block = Self.decodeBlock(row) else {
        throw StoreError.invalidRecord
      }
      state.blocks[block.id] = block
    }
    for row in try Row.fetchAll(db, sql: "SELECT id, content_hash, byte_count FROM assets") {
      guard let asset = Self.decodeAssetRow(row) else {
        throw StoreError.invalidRecord
      }
      state.assets[asset.id] = asset
    }
    return state
  }

  private static func writeProjection(_ state: ReplayState, db: Database) throws {
    try db.execute(sql: "DELETE FROM records")
    try db.execute(sql: "DELETE FROM blocks")
    try db.execute(sql: "DELETE FROM assets")
    for record in state.records.values {
      try db.execute(
        sql: "INSERT INTO records (id, title, revision) VALUES (?, ?, ?)",
        arguments: [record.id.uuidString, record.title, record.revision])
    }
    for block in state.blocks.values {
      try db.execute(
        sql: "INSERT INTO blocks (id, record_id, position, text, revision) VALUES (?, ?, ?, ?, ?)",
        arguments: [
          block.id.uuidString, block.recordID.uuidString, block.position, block.text,
          block.revision,
        ])
    }
    for asset in state.assets.values {
      try db.execute(
        sql: "INSERT INTO assets (id, content_hash, byte_count) VALUES (?, ?, ?)",
        arguments: [asset.id.uuidString, asset.contentHash, asset.byteCount])
    }
  }

  private static func normalizedState(from state: ReplayState) -> Data {
    let recordEntries = state.records.values.map { entry -> [String: Any] in
      ["id": entry.id.uuidString, "title": entry.title, "revision": entry.revision]
    }
    let blockEntries = state.blocks.values.map { entry -> [String: Any] in
      [
        "id": entry.id.uuidString, "recordID": entry.recordID.uuidString,
        "position": entry.position, "text": entry.text, "revision": entry.revision,
      ]
    }
    let assetEntries = state.assets.values.map { entry -> [String: Any] in
      ["id": entry.id.uuidString, "contentHash": entry.contentHash, "byteCount": entry.byteCount]
    }
    let value: [String: Any] = [
      "records": recordEntries.sorted { ($0["id"] as! String) < ($1["id"] as! String) },
      "blocks": blockEntries.sorted { ($0["id"] as! String) < ($1["id"] as! String) },
      "assets": assetEntries.sorted { ($0["id"] as! String) < ($1["id"] as! String) },
    ]
    return try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  }

  private static func decodeRecordRow(_ row: Row?) -> SynoraDomain.Record? {
    guard let row, let idText: String = row["id"], let id = UUID(uuidString: idText),
      let title: String = row["title"], let revision: Int = row["revision"]
    else {
      return nil
    }
    return SynoraDomain.Record(id: id, title: title, revision: revision)
  }

  static func decodeBlock(_ row: Row?) -> Block? {
    guard let row, let idText: String = row["id"], let id = UUID(uuidString: idText),
      let recordText: String = row["record_id"], let recordID = UUID(uuidString: recordText),
      let position: Int = row["position"], let text: String = row["text"],
      let revision: Int = row["revision"]
    else {
      return nil
    }
    return Block(id: id, recordID: recordID, position: position, text: text, revision: revision)
  }

  private static func decodeAssetRow(_ row: Row?) -> Asset? {
    guard let row, let idText: String = row["id"], let id = UUID(uuidString: idText),
      let contentHash: String = row["content_hash"], let byteCount: Int64 = row["byte_count"]
    else {
      return nil
    }
    return Asset(id: id, contentHash: contentHash, byteCount: byteCount)
  }
}
