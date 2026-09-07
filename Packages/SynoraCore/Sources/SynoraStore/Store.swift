import CryptoKit
import Foundation
import GRDB
import SynoraDomain

public typealias DomainRecord = SynoraDomain.Record

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

public struct HistoryEntry: Hashable, Sendable {
  public let sequence: Int64
  public let timestamp: Date
  public let revision: Int
  public let title: String

  public init(sequence: Int64, timestamp: Date, revision: Int, title: String) {
    self.sequence = sequence
    self.timestamp = timestamp
    self.revision = revision
    self.title = title
  }
}

public enum ProductStoreError: Error, Equatable, Sendable {
  case missingRecord
  case invalidDocument
  case operationConflict
  case invalidOperation
  case invalidSnapshot
  case noUndo
  case noRedo
}

public final class ProductStore: @unchecked Sendable {
  private let pool: DatabasePool
  private let clock: any Clock
  private let ids: any IDGenerator
  private var redoStack: [ChangePayload] = []

  public init(
    path: String,
    clock: any Clock = SystemClock(),
    ids: any IDGenerator = UUIDGenerator()
  ) throws {
    self.clock = clock
    self.ids = ids
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    pool = try DatabasePool(path: path)
    try migrate()
  }

  public func migrate() throws {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("p2-document-v1") { db in
      try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS records (
          id TEXT PRIMARY KEY NOT NULL,
          kind TEXT NOT NULL,
          journal_date REAL,
          revision INTEGER NOT NULL,
          payload BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS blocks (
          id TEXT PRIMARY KEY NOT NULL,
          record_id TEXT NOT NULL,
          parent_id TEXT,
          position INTEGER NOT NULL,
          order_key INTEGER NOT NULL,
          payload BLOB NOT NULL
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
          request_hash TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS snapshots (
          up_to_sequence INTEGER PRIMARY KEY NOT NULL,
          normalized_state BLOB NOT NULL,
          sha256 TEXT NOT NULL
        );
        PRAGMA journal_mode = WAL;
        """)
    }
    try migrator.migrate(pool)
  }

  public func records(kind: RecordKind? = nil) throws -> [DomainRecord] {
    try pool.read { db in
      let rows: [Row]
      if let kind {
        rows = try Row.fetchAll(
          db, sql: "SELECT payload FROM records WHERE kind = ? ORDER BY COALESCE(journal_date, 0) DESC, id",
          arguments: [kind.rawValue])
      } else {
        rows = try Row.fetchAll(db, sql: "SELECT payload FROM records ORDER BY id")
      }
      return try rows.map { try Self.decodeRecord($0) }
    }
  }

  public func record(id: UUID) throws -> DomainRecord? {
    try pool.read { db in
      guard let row = try Row.fetchOne(
        db, sql: "SELECT payload FROM records WHERE id = ?", arguments: [id.uuidString])
      else { return nil }
      return try Self.decodeRecord(row)
    }
  }

  public func document(recordID: UUID) throws -> BlockDocument {
    try pool.read { db in try Self.loadDocument(db, recordID: recordID) }
  }

  @discardableResult
  public func save(
    record: DomainRecord,
    document: BlockDocument,
    expectedRevision: Int,
    operationID: UUID? = nil
  ) throws -> StoreReceipt {
    guard record.id == document.recordID else { throw ProductStoreError.invalidDocument }
    try document.validate()
    let operationID = operationID ?? ids.next()
    let request = try Self.encode(Request(record: record, document: document, expectedRevision: expectedRevision))
    let requestHash = Self.fingerprint(request)
    let result = try pool.write { db -> StoreReceipt in
      if let existing = try Row.fetchOne(
        db, sql: "SELECT sequence, entity_revision, request_hash FROM operations WHERE id = ?",
        arguments: [operationID.uuidString]) {
        guard let stored: String = existing["request_hash"], stored == requestHash,
          let sequence: Int64 = existing["sequence"], let revision: Int = existing["entity_revision"]
        else { throw ProductStoreError.operationConflict }
        return StoreReceipt(operationID: operationID, sequence: sequence, revision: revision)
      }

      let previousRecord = try Self.record(db, id: record.id)
      let currentRevision = previousRecord?.revision ?? 0
      guard expectedRevision == currentRevision else {
        throw RevisionError.stale(expected: expectedRevision, actual: currentRevision)
      }
      let persisted = DomainRecord(
        id: record.id, title: record.title, revision: currentRevision + 1,
        kind: record.kind, journalDate: record.journalDate, metadata: record.metadata,
        unknownFields: record.unknownFields)
      let previousDocument = try Self.loadDocument(db, recordID: record.id)
      let change = ChangePayload(
        beforeRecord: previousRecord,
        beforeDocument: previousRecord == nil ? nil : previousDocument,
        afterRecord: persisted,
        afterDocument: document)
      let payload = try Self.encode(change)
      return try self.appendOperation(
        db, operationID: operationID, entityID: record.id, revision: persisted.revision,
        kind: "document.save", payload: payload, requestHash: requestHash
      ) { receipt in
        try Self.writeProjection(persisted, document: document, db: db)
        return receipt
      }
    }
    redoStack.removeAll()
    return result
  }

  @discardableResult
  public func create(
    title: String,
    kind: RecordKind = .note,
    journalDate: Date? = nil,
    metadata: [String: String] = [:],
    operationID: UUID? = nil
  ) throws -> (record: DomainRecord, receipt: StoreReceipt) {
    let newRecord = DomainRecord(
      id: ids.next(), title: title, revision: 0, kind: kind, journalDate: journalDate,
      metadata: metadata)
    let document = try BlockDocument(recordID: newRecord.id, blocks: [])
    let receipt = try save(record: newRecord, document: document, expectedRevision: 0, operationID: operationID)
    guard let saved = try self.record(id: newRecord.id) else { throw ProductStoreError.missingRecord }
    return (saved, receipt)
  }

  public func history(recordID: UUID) throws -> [HistoryEntry] {
    try pool.read { db in
      let rows = try Row.fetchAll(
        db, sql: "SELECT sequence, timestamp, entity_revision, payload FROM operations WHERE entity_id = ? AND kind = 'document.save' ORDER BY sequence DESC",
        arguments: [recordID.uuidString])
      return try rows.map { row in
        let payload: Data = row["payload"]
        let change = try Self.decode(ChangePayload.self, from: payload)
        return HistoryEntry(
          sequence: row["sequence"], timestamp: Date(timeIntervalSince1970: row["timestamp"]),
          revision: row["entity_revision"], title: change.afterRecord.title)
      }
    }
  }

  @discardableResult
  public func undo(recordID: UUID, operationID: UUID? = nil) throws -> StoreReceipt {
    guard let latest = try latestChange(recordID: recordID), let before = latest.beforeRecord,
      let beforeDocument = latest.beforeDocument, let current = try record(id: recordID)
    else { throw ProductStoreError.noUndo }
    let receipt = try save(
      record: before, document: beforeDocument, expectedRevision: current.revision,
      operationID: operationID)
    redoStack.append(latest)
    return receipt
  }

  @discardableResult
  public func redo(recordID: UUID, operationID: UUID? = nil) throws -> StoreReceipt {
    guard let change = redoStack.popLast(), change.afterRecord.id == recordID,
      let current = try record(id: recordID)
    else { throw ProductStoreError.noRedo }
    return try save(
      record: change.afterRecord, document: change.afterDocument, expectedRevision: current.revision,
      operationID: operationID)
  }

  public func operationCount() throws -> Int {
    try pool.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM operations") ?? 0 }
  }

  public func snapshot() throws -> Snapshot {
    try pool.write { db in
      let state = try Self.normalizedState(db)
      let sequence = try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(sequence), 0) FROM operations") ?? 0
      let snapshot = Snapshot(upToSequence: sequence, normalizedState: state)
      try db.execute(
        sql: "INSERT OR REPLACE INTO snapshots (up_to_sequence, normalized_state, sha256) VALUES (?, ?, ?)",
        arguments: [snapshot.upToSequence, snapshot.normalizedState, snapshot.sha256])
      return snapshot
    }
  }

  public func verifyIntegrity() throws {
    try pool.read { db in
      let rows = try Row.fetchAll(db, sql: "SELECT * FROM operations ORDER BY sequence")
      var sequence: Int64 = 0
      var previousHash: String?
      for row in rows {
        guard let idText: String = row["id"], let id = UUID(uuidString: idText),
          let entityText: String = row["entity_id"], let entityID = UUID(uuidString: entityText),
          let storedSequence: Int64 = row["sequence"], storedSequence == sequence + 1,
          let transactionID: Int64 = row["transaction_id"], let revision: Int = row["entity_revision"],
          let kind: String = row["kind"], let payload: Data = row["payload"],
          let timestamp: Double = row["timestamp"], let storedHash: String = row["hash"]
        else { throw ProductStoreError.invalidOperation }
        let operation = Operation(
          id: id, transactionID: transactionID, sequence: storedSequence, entityID: entityID,
          entityRevision: revision, kind: kind, payload: payload,
          timestamp: Date(timeIntervalSince1970: timestamp), previousHash: row["previous_hash"])
        guard operation.previousHash == previousHash, operation.hash == storedHash else {
          throw ProductStoreError.invalidOperation
        }
        sequence = storedSequence
        previousHash = storedHash
      }
    }
  }

  private func latestChange(recordID: UUID) throws -> ChangePayload? {
    try pool.read { db in
      guard let row = try Row.fetchOne(
        db, sql: "SELECT payload FROM operations WHERE entity_id = ? AND kind = 'document.save' ORDER BY sequence DESC LIMIT 1",
        arguments: [recordID.uuidString])
      else { return nil }
      return try Self.decode(ChangePayload.self, from: row["payload"] as Any)
    }
  }

  private func appendOperation(
    _ db: Database,
    operationID: UUID,
    entityID: UUID,
    revision: Int,
    kind: String,
    payload: Data,
    requestHash: String,
    mutate: (StoreReceipt) throws -> StoreReceipt
  ) throws -> StoreReceipt {
    let sequence = try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(sequence), 0) + 1 FROM operations") ?? 1
    let transactionID = try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(transaction_id), 0) + 1 FROM operations") ?? 1
    let previousHash = try String.fetchOne(
      db, sql: "SELECT hash FROM operations ORDER BY sequence DESC LIMIT 1")
    let operation = Operation(
      id: operationID, transactionID: transactionID, sequence: sequence, entityID: entityID,
      entityRevision: revision, kind: kind, payload: payload, timestamp: clock.now(),
      previousHash: previousHash)
    try db.execute(
      sql: "INSERT INTO operations (id, transaction_id, sequence, entity_id, entity_revision, kind, payload, timestamp, previous_hash, hash, request_hash) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      arguments: [
        operation.id.uuidString, operation.transactionID, operation.sequence,
        operation.entityID.uuidString, operation.entityRevision, operation.kind, operation.payload,
        operation.timestamp.timeIntervalSince1970, operation.previousHash, operation.hash, requestHash,
      ])
    return try mutate(StoreReceipt(operationID: operationID, sequence: sequence, revision: revision))
  }

  private struct Request: Codable {
    let record: DomainRecord
    let document: BlockDocument
    let expectedRevision: Int
  }

  private struct ChangePayload: Codable, Hashable, Sendable {
    let beforeRecord: DomainRecord?
    let beforeDocument: BlockDocument?
    let afterRecord: DomainRecord
    let afterDocument: BlockDocument
  }

  private static func loadDocument(_ db: Database, recordID: UUID) throws -> BlockDocument {
    let rows = try Row.fetchAll(
      db, sql: "SELECT payload FROM blocks WHERE record_id = ? ORDER BY order_key, position, id",
      arguments: [recordID.uuidString])
    let blocks = try rows.map { try decode(Block.self, from: $0["payload"] as Any) }
    return try BlockDocument(recordID: recordID, blocks: blocks)
  }

  private static func record(_ db: Database, id: UUID) throws -> DomainRecord? {
    guard let row = try Row.fetchOne(
      db, sql: "SELECT payload FROM records WHERE id = ?", arguments: [id.uuidString])
    else { return nil }
    return try decodeRecord(row)
  }

  private static func decodeRecord(_ row: Row) throws -> DomainRecord {
    try decode(DomainRecord.self, from: row["payload"] as Any)
  }

  private static func writeProjection(_ record: DomainRecord, document: BlockDocument, db: Database) throws {
    let recordPayload = try encode(record)
    try db.execute(
      sql: "INSERT INTO records (id, kind, journal_date, revision, payload) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET kind = excluded.kind, journal_date = excluded.journal_date, revision = excluded.revision, payload = excluded.payload",
      arguments: [record.id.uuidString, record.kind.rawValue, record.journalDate?.timeIntervalSince1970, record.revision, recordPayload])
    try db.execute(sql: "DELETE FROM blocks WHERE record_id = ?", arguments: [record.id.uuidString])
    for block in document.blocks {
      try db.execute(
        sql: "INSERT INTO blocks (id, record_id, parent_id, position, order_key, payload) VALUES (?, ?, ?, ?, ?, ?)",
        arguments: [
          block.id.uuidString, block.recordID.uuidString, block.parentID?.uuidString,
          block.position, block.orderKey, try encode(block),
        ])
    }
  }

  private static func normalizedState(_ db: Database) throws -> Data {
    let records = try Row.fetchAll(db, sql: "SELECT payload FROM records ORDER BY id").map { try decodeRecord($0) }
    let blockRows = try Row.fetchAll(db, sql: "SELECT payload FROM blocks ORDER BY record_id, order_key, id")
    let blocks = try blockRows.map { try decode(Block.self, from: $0["payload"] as Any) }
    return try encode(State(records: records, blocks: blocks))
  }

  private struct State: Codable {
    let records: [DomainRecord]
    let blocks: [Block]
  }

  private static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
  }

  private static func decode<T: Decodable>(_ type: T.Type, from value: Any) throws -> T {
    guard let data = value as? Data else { throw ProductStoreError.invalidOperation }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return try decoder.decode(type, from: data)
  }

  private static func fingerprint(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
