import CryptoKit
import Foundation

public protocol Clock: Sendable {
  func now() -> Date
}

public struct SystemClock: Clock {
  public init() {}

  public func now() -> Date { Date() }
}

public protocol IDGenerator: Sendable {
  func next() -> UUID
}

public struct UUIDGenerator: IDGenerator {
  public init() {}

  public func next() -> UUID { UUID() }
}

public final class FixedIDGenerator: IDGenerator, @unchecked Sendable {
  private let values: [UUID]
  private let lock = NSLock()
  private var index = 0

  public init(_ values: [UUID]) {
    self.values = values
  }

  public func next() -> UUID {
    lock.lock()
    defer { lock.unlock() }
    precondition(index < values.count, "fixed ID sequence exhausted")
    let value = values[index]
    index += 1
    return value
  }
}

public struct Library: Codable, Hashable, Sendable {
  public let id: UUID
  public var name: String
  public var revision: Int

  public init(id: UUID, name: String, revision: Int = 0) {
    self.id = id
    self.name = name
    self.revision = revision
  }
}

public struct Record: Codable, Hashable, Sendable {
  public let id: UUID
  public var title: String
  public var revision: Int

  public init(id: UUID, title: String, revision: Int = 0) {
    self.id = id
    self.title = title
    self.revision = revision
  }
}

public struct Block: Codable, Hashable, Sendable {
  public let id: UUID
  public let recordID: UUID
  public var position: Int
  public var text: String
  public var revision: Int

  public init(id: UUID, recordID: UUID, position: Int, text: String, revision: Int = 0) {
    self.id = id
    self.recordID = recordID
    self.position = position
    self.text = text
    self.revision = revision
  }
}

public struct Asset: Codable, Hashable, Sendable {
  public let id: UUID
  public let contentHash: String
  public let byteCount: Int64

  public init(id: UUID, contentHash: String, byteCount: Int64) {
    self.id = id
    self.contentHash = contentHash
    self.byteCount = byteCount
  }
}

public protocol RecordRepository: Sendable {
  func record(id: UUID) throws -> Record?
  func save(_ record: Record) throws
}

public protocol TransactionRunner: Sendable {
  func inTransaction<T: Sendable>(_ body: @Sendable () throws -> T) throws -> T
}

public struct Operation: Codable, Hashable, Sendable {
  public let id: UUID
  public let transactionID: Int64
  public let sequence: Int64
  public let entityID: UUID
  public let entityRevision: Int
  public let kind: String
  public let payload: Data
  public let timestamp: Date
  public let previousHash: String?
  public let hash: String

  public init(
    id: UUID,
    transactionID: Int64,
    sequence: Int64,
    entityID: UUID,
    entityRevision: Int,
    kind: String,
    payload: Data,
    timestamp: Date,
    previousHash: String?
  ) {
    self.id = id
    self.transactionID = transactionID
    self.sequence = sequence
    self.entityID = entityID
    self.entityRevision = entityRevision
    self.kind = kind
    self.payload = payload
    self.timestamp = timestamp
    self.previousHash = previousHash
    self.hash = Self.computeHash(
      id: id,
      transactionID: transactionID,
      sequence: sequence,
      entityID: entityID,
      entityRevision: entityRevision,
      kind: kind,
      payload: payload,
      timestamp: timestamp,
      previousHash: previousHash
    )
  }

  public var canonicalBytes: Data {
    Self.canonicalBytes(
      id: id,
      transactionID: transactionID,
      sequence: sequence,
      entityID: entityID,
      entityRevision: entityRevision,
      kind: kind,
      payload: payload,
      timestamp: timestamp,
      previousHash: previousHash
    )
  }

  private static func canonicalBytes(
    id: UUID,
    transactionID: Int64,
    sequence: Int64,
    entityID: UUID,
    entityRevision: Int,
    kind: String,
    payload: Data,
    timestamp: Date,
    previousHash: String?
  ) -> Data {
    let value: [String: Any] = [
      "entityID": entityID.uuidString.lowercased(),
      "entityRevision": entityRevision,
      "id": id.uuidString.lowercased(),
      "kind": kind,
      "payload": payload.base64EncodedString(),
      "previousHash": previousHash as Any,
      "sequence": sequence,
      "timestamp": timestamp.timeIntervalSince1970,
      "transactionID": transactionID,
    ]
    return try! JSONSerialization.data(
      withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
  }

  private static func computeHash(
    id: UUID,
    transactionID: Int64,
    sequence: Int64,
    entityID: UUID,
    entityRevision: Int,
    kind: String,
    payload: Data,
    timestamp: Date,
    previousHash: String?
  ) -> String {
    SHA256.hash(
      data: canonicalBytes(
        id: id,
        transactionID: transactionID,
        sequence: sequence,
        entityID: entityID,
        entityRevision: entityRevision,
        kind: kind,
        payload: payload,
        timestamp: timestamp,
        previousHash: previousHash
      )
    ).map { String(format: "%02x", $0) }.joined()
  }
}

public struct Snapshot: Codable, Hashable, Sendable {
  public let upToSequence: Int64
  public let normalizedState: Data
  public let sha256: String

  public init(upToSequence: Int64, normalizedState: Data) {
    self.upToSequence = upToSequence
    self.normalizedState = normalizedState
    self.sha256 = SHA256.hash(data: normalizedState).map { String(format: "%02x", $0) }.joined()
  }

  public func isValid() -> Bool {
    SHA256.hash(data: normalizedState).map { String(format: "%02x", $0) }.joined() == sha256
  }
}

public enum RevisionError: Error, Equatable, Sendable {
  case stale(expected: Int, actual: Int)
}

public enum Revision {
  public static func next(after current: Int, expected: Int) throws -> Int {
    guard current == expected else {
      throw RevisionError.stale(expected: expected, actual: current)
    }
    return current + 1
  }
}
