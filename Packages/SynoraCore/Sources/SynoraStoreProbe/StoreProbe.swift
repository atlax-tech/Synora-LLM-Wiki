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
  case invalidSnapshot
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
            hash TEXT NOT NULL
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
      return SynoraDomain.Record(
        id: UUID(uuidString: row["id"] as String)!,
        title: row["title"],
        revision: row["revision"]
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
    return try pool.write { db in
      if let existing = try Row.fetchOne(
        db, sql: "SELECT sequence, entity_revision FROM operations WHERE id = ?",
        arguments: [operationID.uuidString])
      {
        return StoreReceipt(
          operationID: operationID, sequence: existing["sequence"],
          revision: existing["entity_revision"])
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
      let payload = try JSONEncoder().encode(record)
      let operation = Operation(
        id: operationID,
        transactionID: transactionID,
        sequence: sequence,
        entityID: record.id,
        entityRevision: record.revision + 1,
        kind: "record.save",
        payload: payload,
        timestamp: clock.now(),
        previousHash: previousHash
      )
      try db.execute(
        sql: """
          INSERT INTO operations
            (id, transaction_id, sequence, entity_id, entity_revision, kind, payload, timestamp, previous_hash, hash)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
      let state = records.map {
        [
          "id": $0["id"] as String, "title": $0["title"] as String,
          "revision": $0["revision"] as Int,
        ]
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
      guard
        let row = try Row.fetchOne(
          db,
          sql:
            "SELECT up_to_sequence, normalized_state, sha256 FROM snapshots ORDER BY up_to_sequence DESC LIMIT 1"
        )
      else {
        return nil
      }
      let snapshot = Snapshot(
        upToSequence: row["up_to_sequence"], normalizedState: row["normalized_state"])
      return snapshot.sha256 == (row["sha256"] as String) ? snapshot : nil
    }
  }

  public func projectionHash() throws -> String {
    let snapshot = try snapshot()
    return snapshot.sha256
  }
}
