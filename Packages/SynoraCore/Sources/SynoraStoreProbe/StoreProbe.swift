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

      let sequence =
        (try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(sequence), 0) + 1 FROM operations")) ?? 1
      let transactionID =
        (try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(transaction_id), 0) + 1 FROM operations"))
        ?? 1
      let previousHash = try String.fetchOne(
        db, sql: "SELECT hash FROM operations ORDER BY sequence DESC LIMIT 1")
      let nextRevision = record.revision + 1
      let persistedRecord = SynoraDomain.Record(
        id: record.id, title: record.title, revision: nextRevision)
      let payload = try JSONEncoder().encode(persistedRecord)
      let operation = Operation(
        id: operationID,
        transactionID: transactionID,
        sequence: sequence,
        entityID: record.id,
        entityRevision: nextRevision,
        kind: "record.save",
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
      try db.execute(
        sql:
          "INSERT INTO records (id, title, revision) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET title = excluded.title, revision = excluded.revision",
        arguments: [record.id.uuidString, record.title, operation.entityRevision]
      )
      return StoreReceipt(
        operationID: operation.id, sequence: operation.sequence, revision: operation.entityRevision)
    }
  }

  public func operationCount() throws -> Int {
    try pool.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM operations") ?? 0
    }
  }

  public func snapshot() throws -> Snapshot {
    try pool.write { db in
      let records = try Row.fetchAll(db, sql: "SELECT id, title, revision FROM records ORDER BY id")
      let state = try records.map { row -> [String: Any] in
        guard let id: String = row["id"], let title: String = row["title"],
          let revision: Int = row["revision"]
        else {
          throw StoreError.invalidRecord
        }
        return ["id": id, "title": title, "revision": revision]
      }
      let normalized = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
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

  public func projectionHash() throws -> String {
    let snapshot = try snapshot()
    return snapshot.sha256
  }

  private func requestHash(for record: SynoraDomain.Record) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = (try? encoder.encode(record)) ?? Data()
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
