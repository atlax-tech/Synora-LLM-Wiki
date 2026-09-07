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

public enum RecordKind: String, Codable, CaseIterable, Hashable, Sendable {
  case note
  case journal
}

public enum BlockType: Codable, Hashable, Sendable {
  case paragraph
  case heading1
  case heading2
  case heading3
  case bulletedList
  case numberedList
  case task
  case quote
  case code
  case divider
  case table
  case toggle
  case callout
  case image
  case gallery
  case video
  case audio
  case pdf
  case file
  case link
  case unknown(String)

  private var wireValue: String {
    switch self {
    case .paragraph: "paragraph"
    case .heading1: "heading1"
    case .heading2: "heading2"
    case .heading3: "heading3"
    case .bulletedList: "bulleted-list"
    case .numberedList: "numbered-list"
    case .task: "task"
    case .quote: "quote"
    case .code: "code"
    case .divider: "divider"
    case .table: "table"
    case .toggle: "toggle"
    case .callout: "callout"
    case .image: "image"
    case .gallery: "gallery"
    case .video: "video"
    case .audio: "audio"
    case .pdf: "pdf"
    case .file: "file"
    case .link: "link"
    case .unknown(let value): value
    }
  }

  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    switch value {
    case "paragraph": self = .paragraph
    case "heading1": self = .heading1
    case "heading2": self = .heading2
    case "heading3": self = .heading3
    case "bulleted-list": self = .bulletedList
    case "numbered-list": self = .numberedList
    case "task": self = .task
    case "quote": self = .quote
    case "code": self = .code
    case "divider": self = .divider
    case "table": self = .table
    case "toggle": self = .toggle
    case "callout": self = .callout
    case "image": self = .image
    case "gallery": self = .gallery
    case "video": self = .video
    case "audio": self = .audio
    case "pdf": self = .pdf
    case "file": self = .file
    case "link": self = .link
    default: self = .unknown(value)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(wireValue)
  }

  public var acceptsChildren: Bool {
    switch self {
    case .bulletedList, .numberedList, .quote, .table, .toggle, .callout, .gallery:
      true
    default:
      false
    }
  }
}

public enum JSONValue: Codable, Hashable, Sendable {
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() { self = .null }
    else if let value = try? container.decode(Bool.self) { self = .bool(value) }
    else if let value = try? container.decode(Double.self) { self = .number(value) }
    else if let value = try? container.decode(String.self) { self = .string(value) }
    else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
    else { self = .object(try container.decode([String: JSONValue].self)) }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .object(let value): try value.encode(to: encoder)
    case .array(let value): try value.encode(to: encoder)
    case .string(let value): try value.encode(to: encoder)
    case .number(let value): try value.encode(to: encoder)
    case .bool(let value): try value.encode(to: encoder)
    case .null: var container = encoder.singleValueContainer(); try container.encodeNil()
    }
  }
}

public struct Record: Codable, Hashable, Sendable {
  public let id: UUID
  public var title: String
  public var revision: Int
  public var kind: RecordKind
  public var journalDate: Date?
  public var metadata: [String: String]
  public var unknownFields: [String: JSONValue]

  public init(
    id: UUID,
    title: String,
    revision: Int = 0,
    kind: RecordKind = .note,
    journalDate: Date? = nil,
    metadata: [String: String] = [:],
    unknownFields: [String: JSONValue] = [:]
  ) {
    self.id = id
    self.title = title
    self.revision = revision
    self.kind = kind
    self.journalDate = journalDate
    self.metadata = metadata
    self.unknownFields = unknownFields
  }

  public init(id: UUID, title: String, revision: Int) {
    self.init(id: id, title: title, revision: revision, kind: .note)
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, revision, kind, journalDate, metadata, unknownFields
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(UUID.self, forKey: .id),
      title: try container.decode(String.self, forKey: .title),
      revision: try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0,
      kind: try container.decodeIfPresent(RecordKind.self, forKey: .kind) ?? .note,
      journalDate: try container.decodeIfPresent(Date.self, forKey: .journalDate),
      metadata: try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:],
      unknownFields: try container.decodeIfPresent([String: JSONValue].self, forKey: .unknownFields) ?? [:]
    )
  }
}

public struct Block: Codable, Hashable, Sendable {
  public let id: UUID
  public let recordID: UUID
  public var parentID: UUID?
  public var type: BlockType
  public var orderKey: Int64
  public var position: Int
  public var text: String
  public var attributes: [String: String]
  public var unknownFields: [String: JSONValue]
  public var revision: Int

  public init(
    id: UUID,
    recordID: UUID,
    position: Int,
    text: String,
    revision: Int = 0,
    parentID: UUID? = nil,
    type: BlockType = .paragraph,
    orderKey: Int64? = nil,
    attributes: [String: String] = [:],
    unknownFields: [String: JSONValue] = [:]
  ) {
    self.id = id
    self.recordID = recordID
    self.parentID = parentID
    self.type = type
    self.orderKey = orderKey ?? Int64(position) * 1024
    self.position = position
    self.text = text
    self.attributes = attributes
    self.unknownFields = unknownFields
    self.revision = revision
  }

  public init(id: UUID, recordID: UUID, position: Int, text: String, revision: Int) {
    self.init(
      id: id, recordID: recordID, position: position, text: text, revision: revision,
      parentID: nil, type: .paragraph, orderKey: Int64(position) * 1024)
  }

  private enum CodingKeys: String, CodingKey {
    case id, recordID, parentID, type, orderKey, position, text, attributes, unknownFields, revision
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
    self.init(
      id: try container.decode(UUID.self, forKey: .id),
      recordID: try container.decode(UUID.self, forKey: .recordID),
      position: position,
      text: try container.decodeIfPresent(String.self, forKey: .text) ?? "",
      revision: try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0,
      parentID: try container.decodeIfPresent(UUID.self, forKey: .parentID),
      type: try container.decodeIfPresent(BlockType.self, forKey: .type) ?? .paragraph,
      orderKey: try container.decodeIfPresent(Int64.self, forKey: .orderKey) ?? Int64(position) * 1024,
      attributes: try container.decodeIfPresent([String: String].self, forKey: .attributes) ?? [:],
      unknownFields: try container.decodeIfPresent([String: JSONValue].self, forKey: .unknownFields) ?? [:]
    )
  }
}

public enum BlockTreeError: Error, Equatable, Sendable {
  case duplicateID(UUID)
  case missingParent(UUID)
  case crossRecordParent(UUID)
  case cycle(UUID)
  case invalidChild(UUID)
}

public struct BlockDocument: Codable, Hashable, Sendable {
  public let recordID: UUID
  public private(set) var blocks: [Block]

  public init(recordID: UUID, blocks: [Block] = []) throws {
    self.recordID = recordID
    self.blocks = blocks
    try validate()
  }

  public func validate() throws {
    var IDs = Set<UUID>()
    var blockByID: [UUID: Block] = [:]
    for block in blocks {
      guard IDs.insert(block.id).inserted else { throw BlockTreeError.duplicateID(block.id) }
      blockByID[block.id] = block
      guard block.recordID == recordID else { throw BlockTreeError.crossRecordParent(block.id) }
      guard block.parentID != block.id else { throw BlockTreeError.cycle(block.id) }
      if let parentID = block.parentID {
        guard let parent = blockByID[parentID] else { throw BlockTreeError.missingParent(parentID) }
        guard parent.recordID == recordID else { throw BlockTreeError.crossRecordParent(block.id) }
        guard parent.type.acceptsChildren else { throw BlockTreeError.invalidChild(block.id) }
        var ancestor = parentID
        var visited = Set<UUID>()
        while let current = blockByID[ancestor] {
          guard visited.insert(current.id).inserted else { throw BlockTreeError.cycle(block.id) }
          if current.parentID == block.id { throw BlockTreeError.cycle(block.id) }
          guard let next = current.parentID else { break }
          ancestor = next
        }
      }
    }
  }

  public func children(of parentID: UUID? = nil) -> [Block] {
    blocks.filter { $0.parentID == parentID }.sorted {
      ($0.orderKey, $0.id.uuidString) < ($1.orderKey, $1.id.uuidString)
    }
  }

  public func block(id: UUID) -> Block? { blocks.first { $0.id == id } }

  public func inserting(_ block: Block, before siblingID: UUID? = nil) throws -> Self {
    var copy = self
    var inserted = block
    let siblings = children(of: block.parentID)
    let index = siblingID.flatMap { sibling in siblings.firstIndex { $0.id == sibling } } ?? siblings.count
    let previous = index > 0 ? siblings[index - 1].orderKey : nil
    let next = index < siblings.count ? siblings[index].orderKey : nil
    inserted.orderKey = Self.orderKey(previous: previous, next: next)
    inserted.position = index
    copy.blocks.append(inserted)
    try copy.validate()
    return copy
  }

  public func moving(id: UUID, to parentID: UUID?, before siblingID: UUID? = nil) throws -> Self {
    guard let source = block(id: id) else { throw BlockTreeError.missingParent(id) }
    var copy = self
    copy.blocks.removeAll { $0.id == id }
    var moved = source
    moved.parentID = parentID
    return try copy.inserting(moved, before: siblingID)
  }

  public func deleting(id: UUID) throws -> Self {
    guard block(id: id) != nil else { throw BlockTreeError.missingParent(id) }
    let removed = Set([id] + descendants(of: id).map(\.id))
    return try Self(recordID: recordID, blocks: blocks.filter { !removed.contains($0.id) })
  }

  public func descendants(of id: UUID) -> [Block] {
    var result: [Block] = []
    var pending = [id]
    while let parent = pending.popLast() {
      let children = blocks.filter { $0.parentID == parent }
      result.append(contentsOf: children)
      pending.append(contentsOf: children.map(\.id))
    }
    return result
  }

  private static func orderKey(previous: Int64?, next: Int64?) -> Int64 {
    switch (previous, next) {
    case let (left?, right?) where right - left > 1: return left + (right - left) / 2
    case let (left?, nil): return left + 1024
    case let (nil, right?): return right - 1024
    default: return 0
    }
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
