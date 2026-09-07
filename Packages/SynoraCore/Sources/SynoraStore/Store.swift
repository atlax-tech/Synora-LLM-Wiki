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

public struct HistoryVersion: Hashable, Sendable {
  public let entry: HistoryEntry
  public let record: DomainRecord
  public let document: BlockDocument

  public init(entry: HistoryEntry, record: DomainRecord, document: BlockDocument) {
    self.entry = entry
    self.record = record
    self.document = document
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
  case templateWouldReplaceContent
  case assetConflict
}

public final class ProductStore: @unchecked Sendable {
  private typealias ChangePayload = ChangeSet
  private let pool: DatabasePool
  private let clock: any Clock
  private let ids: any IDGenerator
  private let historyLock = NSLock()

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
        CREATE TABLE IF NOT EXISTS templates (
          id TEXT PRIMARY KEY NOT NULL,
          kind TEXT NOT NULL,
          payload BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS assets (
          id TEXT PRIMARY KEY NOT NULL,
          content_hash TEXT NOT NULL,
          byte_count INTEGER NOT NULL,
          media_type TEXT,
          original_filename TEXT
        );
        PRAGMA journal_mode = WAL;
        """)
    }
    migrator.registerMigration("p2-templates-v1") { db in
      try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS templates (
          id TEXT PRIMARY KEY NOT NULL,
          kind TEXT NOT NULL,
          payload BLOB NOT NULL
        );
        """)
    }
    migrator.registerMigration("p2-assets-v1") { db in
      try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS assets (
          id TEXT PRIMARY KEY NOT NULL,
          content_hash TEXT NOT NULL,
          byte_count INTEGER NOT NULL,
          media_type TEXT,
          original_filename TEXT
        );
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

  public func saveAsset(_ asset: Asset) throws {
    try pool.write { db in
      try Self.upsertAsset(asset, db: db)
    }
  }

  @discardableResult
  public func saveAsset(
    _ asset: Asset,
    record: DomainRecord,
    document: BlockDocument,
    expectedRevision: Int,
    operationID: UUID? = nil
  ) throws -> StoreReceipt {
    guard Self.references(asset.id, in: document) else {
      throw ProductStoreError.invalidDocument
    }
    var request = try Self.encode(Request(
      record: record, document: document, expectedRevision: expectedRevision))
    request.append(try Self.encode(asset))
    return try save(
      record: record,
      document: document,
      expectedRevision: expectedRevision,
      operationID: operationID,
      asset: asset,
      requestHash: Self.fingerprint(request))
  }

  public func asset(id: UUID) throws -> Asset? {
    try pool.read { db in
      guard let row = try Row.fetchOne(db, sql: "SELECT id, content_hash, byte_count, media_type, original_filename FROM assets WHERE id = ?", arguments: [id.uuidString]),
        let idText: String = row["id"], let storedID = UUID(uuidString: idText),
        let hash: String = row["content_hash"], let count: Int64 = row["byte_count"]
      else { return nil }
      return Asset(
        id: storedID,
        contentHash: hash,
        byteCount: count,
        mediaType: row["media_type"],
        originalFilename: row["original_filename"])
    }
  }

  public func assets() throws -> [Asset] {
    try pool.read { db in
      try Row.fetchAll(db, sql: "SELECT id, content_hash, byte_count, media_type, original_filename FROM assets ORDER BY id").compactMap { row in
        guard let idText: String = row["id"], let id = UUID(uuidString: idText),
          let hash: String = row["content_hash"], let count: Int64 = row["byte_count"] else { return nil }
        return Asset(id: id, contentHash: hash, byteCount: count, mediaType: row["media_type"], originalFilename: row["original_filename"])
      }
    }
  }

  public func saveTemplate(_ template: RecordTemplate) throws {
    let validated = try template.validated()
    try pool.write { db in
      try db.execute(
        sql: "INSERT INTO templates (id, kind, payload) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET kind = excluded.kind, payload = excluded.payload",
        arguments: [validated.id.uuidString, validated.kind.rawValue, try Self.encode(validated)])
    }
  }

  public func templates(kind: RecordKind? = nil) throws -> [RecordTemplate] {
    try pool.read { db in
      let rows: [Row]
      if let kind {
        rows = try Row.fetchAll(
          db, sql: "SELECT payload FROM templates WHERE kind = ? ORDER BY id",
          arguments: [kind.rawValue])
      } else {
        rows = try Row.fetchAll(db, sql: "SELECT payload FROM templates ORDER BY id")
      }
      return try rows.map { try Self.decode(RecordTemplate.self, from: $0["payload"] as Any) }
    }
  }

  public func template(id: UUID) throws -> RecordTemplate? {
    try pool.read { db in
      guard let row = try Row.fetchOne(
        db, sql: "SELECT payload FROM templates WHERE id = ?", arguments: [id.uuidString])
      else { return nil }
      return try Self.decode(RecordTemplate.self, from: row["payload"] as Any)
    }
  }

  public func deleteTemplate(id: UUID) throws {
    try pool.write { db in
      try db.execute(sql: "DELETE FROM templates WHERE id = ?", arguments: [id.uuidString])
    }
  }

  @discardableResult
  public func applyTemplate(
    _ template: RecordTemplate,
    to recordID: UUID,
    expectedRevision: Int,
    replaceExisting: Bool = false,
    operationID: UUID? = nil
  ) throws -> StoreReceipt {
    guard let current = try record(id: recordID) else { throw ProductStoreError.missingRecord }
    let existing = try document(recordID: recordID)
    guard replaceExisting || existing.blocks.isEmpty else {
      throw ProductStoreError.templateWouldReplaceContent
    }
    let document = try Self.copyTemplate(template, to: recordID, ids: ids)
    var record = current
    record.kind = template.kind
    record.metadata.merge(template.metadata) { _, replacement in replacement }
    return try save(
      record: record,
      document: document,
      expectedRevision: expectedRevision,
      operationID: operationID
    )
  }

  @discardableResult
  public func save(
    record: DomainRecord,
    document: BlockDocument,
    expectedRevision: Int,
    operationID: UUID? = nil
  ) throws -> StoreReceipt {
    try save(
      record: record,
      document: document,
      expectedRevision: expectedRevision,
      operationID: operationID,
      asset: nil,
      requestHash: nil)
  }

  @discardableResult
  public func save(
    asset: Asset,
    record: DomainRecord,
    document: BlockDocument,
    expectedRevision: Int,
    operationID: UUID? = nil
  ) throws -> StoreReceipt {
    try saveAsset(
      asset,
      record: record,
      document: document,
      expectedRevision: expectedRevision,
      operationID: operationID)
  }

  private func save(
    record: DomainRecord,
    document: BlockDocument,
    expectedRevision: Int,
    operationID: UUID?,
    asset: Asset?,
    requestHash: String?,
    operationKind: String = "document.save",
    journalPayload: Data? = nil
  ) throws -> StoreReceipt {
    guard record.id == document.recordID else { throw ProductStoreError.invalidDocument }
    try document.validate()
    let operationID = operationID ?? ids.next()
    let request = try Self.encode(Request(record: record, document: document, expectedRevision: expectedRevision))
    let requestHash = requestHash ?? Self.fingerprint(request)
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
      let payload: Data
      if let journalPayload {
        payload = journalPayload
      } else {
        payload = try Self.encode(change)
      }
      return try self.appendOperation(
        db, operationID: operationID, entityID: record.id, revision: persisted.revision,
        kind: operationKind, payload: payload, requestHash: requestHash
      ) { receipt in
        if let asset { try Self.upsertAsset(asset, db: db) }
        try Self.writeProjection(persisted, document: document, db: db)
        return receipt
      }
    }
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

  @discardableResult
  public func updateMetadata(
    recordID: UUID,
    metadata: [String: String],
    expectedRevision: Int,
    operationID: UUID? = nil
  ) throws -> StoreReceipt {
    guard var record = try record(id: recordID) else { throw ProductStoreError.missingRecord }
    record.metadata = metadata
    return try save(
      record: record,
      document: try document(recordID: recordID),
      expectedRevision: expectedRevision,
      operationID: operationID)
  }

  public func history(recordID: UUID) throws -> [HistoryEntry] {
    try pool.read { db in
      let rows = try Row.fetchAll(
        db, sql: "SELECT sequence, timestamp, entity_revision, payload FROM operations WHERE entity_id = ? AND kind IN ('document.save', 'document.restore') ORDER BY sequence DESC",
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

  public func version(recordID: UUID, sequence: Int64) throws -> HistoryVersion? {
    try pool.read { db in
      guard let row = try Row.fetchOne(
        db,
        sql: "SELECT sequence, timestamp, entity_revision, payload FROM operations WHERE entity_id = ? AND kind IN ('document.save', 'document.restore') AND sequence = ?",
        arguments: [recordID.uuidString, sequence]),
        let payload: Data = row["payload"]
      else { return nil }
      let change = try Self.decode(ChangePayload.self, from: payload)
      let entry = HistoryEntry(
        sequence: row["sequence"], timestamp: Date(timeIntervalSince1970: row["timestamp"]),
        revision: row["entity_revision"], title: change.afterRecord.title)
      return HistoryVersion(entry: entry, record: change.afterRecord, document: change.afterDocument)
    }
  }

  @discardableResult
  public func restore(
    recordID: UUID,
    sequence: Int64,
    operationID: UUID? = nil
  ) throws -> StoreReceipt {
    guard let version = try version(recordID: recordID, sequence: sequence),
      let current = try record(id: recordID)
    else { throw ProductStoreError.missingRecord }
    return try save(
      record: version.record,
      document: version.document,
      expectedRevision: current.revision,
      operationID: operationID,
      asset: nil,
      requestHash: nil,
      operationKind: "document.restore"
    )
  }

  @discardableResult
  public func undo(recordID: UUID, operationID: UUID? = nil) throws -> StoreReceipt {
    historyLock.lock()
    defer { historyLock.unlock() }
    let stacks = try actionStacks(recordID: recordID)
    guard let latest = stacks.undo.last, let before = latest.beforeRecord,
      let beforeDocument = latest.beforeDocument, let current = try record(id: recordID)
    else { throw ProductStoreError.noUndo }
    return try save(
      record: before, document: beforeDocument, expectedRevision: current.revision,
      operationID: operationID,
      asset: nil,
      requestHash: nil,
      operationKind: "document.undo",
      journalPayload: try Self.encode(latest))
  }

  @discardableResult
  public func redo(recordID: UUID, operationID: UUID? = nil) throws -> StoreReceipt {
    historyLock.lock()
    defer { historyLock.unlock() }
    let stacks = try actionStacks(recordID: recordID)
    guard let change = stacks.redo.last, change.afterRecord.id == recordID,
      let current = try record(id: recordID)
    else { throw ProductStoreError.noRedo }
    return try save(
      record: change.afterRecord, document: change.afterDocument, expectedRevision: current.revision,
      operationID: operationID,
      asset: nil,
      requestHash: nil,
      operationKind: "document.redo",
      journalPayload: try Self.encode(change))
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

  public func latestSnapshot() throws -> Snapshot? {
    try pool.read { db in
      guard let row = try Row.fetchOne(
        db,
        sql: "SELECT up_to_sequence, normalized_state, sha256 FROM snapshots ORDER BY up_to_sequence DESC LIMIT 1"),
        let sequence: Int64 = row["up_to_sequence"],
        let state: Data = row["normalized_state"],
        let sha256: String = row["sha256"]
      else { return nil }
      let snapshot = Snapshot(upToSequence: sequence, normalizedState: state)
      guard snapshot.sha256 == sha256, snapshot.isValid() else {
        throw ProductStoreError.invalidSnapshot
      }
      return snapshot
    }
  }

  public func stateDigest() throws -> String {
    try pool.read { db in
      Self.fingerprint(try Self.normalizedState(db))
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

  private func actionStacks(recordID: UUID) throws -> (undo: [ChangePayload], redo: [ChangePayload]) {
    try pool.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: "SELECT kind, payload FROM operations WHERE entity_id = ? ORDER BY sequence",
        arguments: [recordID.uuidString])
      var undo: [ChangePayload] = []
      var redo: [ChangePayload] = []
      for row in rows {
        let kind: String = row["kind"]
        switch kind {
        case "document.save", "document.restore":
          let change = try Self.decode(ChangePayload.self, from: row["payload"] as Any)
          undo.append(change)
          redo.removeAll()
        case "document.undo":
          let change = try Self.decode(ChangePayload.self, from: row["payload"] as Any)
          guard undo.last == change else { throw ProductStoreError.invalidOperation }
          _ = undo.popLast()
          redo.append(change)
        case "document.redo":
          let change = try Self.decode(ChangePayload.self, from: row["payload"] as Any)
          guard redo.last == change else { throw ProductStoreError.invalidOperation }
          _ = redo.popLast()
          undo.append(change)
        default:
          continue
        }
      }
      // ponytail: replay the immutable log instead of another persistence table; add indexed
      // cursor state only if profiling shows long undo histories are a bottleneck.
      return (undo, redo)
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
    let receipt = try mutate(StoreReceipt(operationID: operationID, sequence: sequence, revision: revision))
    if sequence.isMultiple(of: 100) {
      let state = try Self.normalizedState(db)
      let snapshot = Snapshot(upToSequence: sequence, normalizedState: state)
      try db.execute(
        sql: "INSERT OR REPLACE INTO snapshots (up_to_sequence, normalized_state, sha256) VALUES (?, ?, ?)",
        arguments: [snapshot.upToSequence, snapshot.normalizedState, snapshot.sha256])
    }
    return receipt
  }

  private struct Request: Codable {
    let record: DomainRecord
    let document: BlockDocument
    let expectedRevision: Int
  }

  private static func loadDocument(_ db: Database, recordID: UUID) throws -> BlockDocument {
    let rows = try Row.fetchAll(
      db, sql: "SELECT payload FROM blocks WHERE record_id = ? ORDER BY order_key, position, id",
      arguments: [recordID.uuidString])
    let blocks = try rows.map { try decode(Block.self, from: $0["payload"] as Any) }
    return try BlockDocument(recordID: recordID, blocks: blocks)
  }

  private static func copyTemplate(
    _ template: RecordTemplate,
    to recordID: UUID,
    ids: any IDGenerator
  ) throws -> BlockDocument {
    var remap: [UUID: UUID] = [:]
    for block in template.blocks { remap[block.id] = ids.next() }
    let copied = template.blocks.map { block in
      Block(
        id: remap[block.id]!,
        recordID: recordID,
        position: block.position,
        text: block.text,
        revision: 0,
        parentID: block.parentID.flatMap { remap[$0] },
        type: block.type,
        orderKey: block.orderKey,
        inlineAttributes: block.inlineAttributes,
        attributes: block.attributes,
        unknownFields: block.unknownFields,
        content: copyContent(block.content)
      )
    }
    return try BlockDocument(recordID: recordID, blocks: copied)
  }

  private static func copyContent(_ content: BlockContent?) -> BlockContent? {
    guard let content else { return nil }
    switch content {
    case .assets(let placements):
      return .assets(placements)
    case .table, .link, .raw:
      return content
    }
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

  private static func references(_ assetID: UUID, in document: BlockDocument) -> Bool {
    document.blocks.contains { block in
      guard case .assets(let placements) = block.content else { return false }
      return placements.contains { $0.assetID == assetID }
    }
  }

  private static func upsertAsset(_ asset: Asset, db: Database) throws {
    if let existing = try Row.fetchOne(
      db,
      sql: "SELECT content_hash, byte_count FROM assets WHERE id = ?",
      arguments: [asset.id.uuidString]) {
      let hash: String = existing["content_hash"]
      let byteCount: Int64 = existing["byte_count"]
      guard hash == asset.contentHash, byteCount == asset.byteCount else {
        throw ProductStoreError.assetConflict
      }
    }
    try db.execute(
      sql: "INSERT INTO assets (id, content_hash, byte_count, media_type, original_filename) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET media_type = excluded.media_type, original_filename = excluded.original_filename",
      arguments: [asset.id.uuidString, asset.contentHash, asset.byteCount, asset.mediaType, asset.originalFilename])
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
