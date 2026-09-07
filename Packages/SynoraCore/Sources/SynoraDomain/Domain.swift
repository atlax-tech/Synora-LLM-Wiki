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
    case .bulletedList, .numberedList, .task, .quote, .toggle, .callout:
      true
    default:
      false
    }
  }

  public var isList: Bool {
    switch self {
    case .bulletedList, .numberedList, .task: true
    default: false
    }
  }

  public var supportsTextEditing: Bool {
    switch self {
    case .paragraph, .heading1, .heading2, .heading3, .bulletedList, .numberedList, .task,
      .quote, .code, .toggle, .callout:
      true
    default:
      false
    }
  }

  public var accessibilityName: String {
    switch self {
    case .paragraph: "Paragraph"
    case .heading1: "Heading 1"
    case .heading2: "Heading 2"
    case .heading3: "Heading 3"
    case .bulletedList: "Bulleted list item"
    case .numberedList: "Numbered list item"
    case .task: "Task"
    case .quote: "Quote"
    case .code: "Code"
    case .divider: "Divider"
    case .table: "Table"
    case .toggle: "Toggle"
    case .callout: "Callout"
    case .image: "Image"
    case .gallery: "Gallery"
    case .video: "Video"
    case .audio: "Audio"
    case .pdf: "PDF"
    case .file: "File"
    case .link: "Link"
    case .unknown: "Unknown block"
    }
  }
}

public enum CalloutStyle: String, Codable, CaseIterable, Hashable, Sendable {
  case neutral
  case info
  case success
  case warning
  case danger
  case error
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

public struct TableCell: Codable, Hashable, Sendable {
  public var text: String
  public var attributes: [String: String]

  public init(text: String = "", attributes: [String: String] = [:]) {
    self.text = text
    self.attributes = attributes
  }
}

public struct TableCellPosition: Codable, Hashable, Sendable {
  public let row: Int
  public let column: Int

  public init(row: Int, column: Int) {
    self.row = row
    self.column = column
  }
}

public enum TableNavigationDirection: String, Codable, CaseIterable, Hashable, Sendable {
  case previous
  case next
  case up
  case down
  case left
  case right
}

public struct TableContent: Codable, Hashable, Sendable {
  public var rows: [[TableCell]]

  public init(rows: [[TableCell]] = []) {
    let width = rows.map(\.count).max() ?? 0
    self.rows = rows.map { row in
      row + Array(repeating: TableCell(), count: width - row.count)
    }
  }

  public init(from decoder: Decoder) throws {
    self.init(rows: try decoder.singleValueContainer().decode([[TableCell]].self))
  }

  public func encode(to encoder: Encoder) throws {
    try rows.encode(to: encoder)
  }

  public var columnCount: Int { rows.map(\.count).max() ?? 0 }

  public var isRectangular: Bool { rows.allSatisfy { $0.count == columnCount } }

  public func cell(at position: TableCellPosition) -> TableCell? {
    guard rows.indices.contains(position.row), rows[position.row].indices.contains(position.column)
    else { return nil }
    return rows[position.row][position.column]
  }

  public func cell(atRow row: Int, column: Int) -> TableCell? {
    cell(at: TableCellPosition(row: row, column: column))
  }

  @discardableResult
  public mutating func setCellText(at position: TableCellPosition, to text: String) -> Bool {
    guard rows.indices.contains(position.row), rows[position.row].indices.contains(position.column)
    else { return false }
    rows[position.row][position.column].text = text
    return true
  }

  @discardableResult
  public mutating func editingCell(atRow row: Int, column: Int, text: String) -> Bool {
    setCellText(at: TableCellPosition(row: row, column: column), to: text)
  }

  public func navigating(
    from position: TableCellPosition,
    direction: TableNavigationDirection
  ) -> TableCellPosition? {
    guard rows.indices.contains(position.row), position.column >= 0,
      position.column < columnCount else { return nil }
    switch direction {
    case .left:
      guard position.column > 0 else { return nil }
      return TableCellPosition(row: position.row, column: position.column - 1)
    case .right:
      guard position.column + 1 < columnCount else { return nil }
      return TableCellPosition(row: position.row, column: position.column + 1)
    case .up:
      guard position.row > 0 else { return nil }
      return TableCellPosition(row: position.row - 1, column: position.column)
    case .down:
      guard position.row + 1 < rows.count else { return nil }
      return TableCellPosition(row: position.row + 1, column: position.column)
    case .previous:
      if position.column > 0 {
        return TableCellPosition(row: position.row, column: position.column - 1)
      }
      guard position.row > 0 else { return nil }
      return TableCellPosition(row: position.row - 1, column: columnCount - 1)
    case .next:
      if position.column + 1 < columnCount {
        return TableCellPosition(row: position.row, column: position.column + 1)
      }
      guard position.row + 1 < rows.count else { return nil }
      return TableCellPosition(row: position.row + 1, column: 0)
    }
  }

  public mutating func insertRow(at index: Int? = nil) {
    let count = columnCount
    let row = Array(repeating: TableCell(), count: count)
    let insertion = min(max(index ?? rows.count, 0), rows.count)
    rows.insert(row, at: insertion)
  }

  public mutating func removeRow(at index: Int) {
    guard rows.indices.contains(index) else { return }
    rows.remove(at: index)
  }

  public mutating func insertColumn(at index: Int? = nil) {
    if rows.isEmpty {
      rows = [[TableCell()]]
      return
    }
    let insertion = min(max(index ?? columnCount, 0), columnCount)
    for rowIndex in rows.indices {
      rows[rowIndex].insert(TableCell(), at: min(insertion, rows[rowIndex].count))
    }
  }

  public mutating func removeColumn(at index: Int) {
    guard index >= 0 else { return }
    for rowIndex in rows.indices where rows[rowIndex].indices.contains(index) {
      rows[rowIndex].remove(at: index)
    }
  }
}

public struct AssetPlacement: Codable, Hashable, Sendable {
  public let assetID: UUID
  public var order: Int
  public var caption: String
  public var crop: [String: Double]

  public init(assetID: UUID, order: Int = 0, caption: String = "", crop: [String: Double] = [:]) {
    self.assetID = assetID
    self.order = order
    self.caption = caption
    self.crop = crop
  }
}

public struct LinkCard: Codable, Hashable, Sendable {
  public let url: String
  public var title: String?
  public var summary: String?

  public init(url: String, title: String? = nil, summary: String? = nil) {
    self.url = url
    self.title = title
    self.summary = summary
  }
}

public enum BlockContent: Codable, Hashable, Sendable {
  case table(TableContent)
  case assets([AssetPlacement])
  case link(LinkCard)
  case raw(JSONValue)
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

public struct RecordTemplate: Codable, Hashable, Sendable {
  public let id: UUID
  public var name: String
  public var kind: RecordKind
  public var blocks: [Block]
  public var metadata: [String: String]

  public init(
    id: UUID = UUID(),
    name: String,
    kind: RecordKind = .note,
    blocks: [Block] = [],
    metadata: [String: String] = [:]
  ) {
    self.id = id
    self.name = name
    self.kind = kind
    self.blocks = blocks
    self.metadata = metadata
  }

  public func validated() throws -> Self {
    let recordID = blocks.first?.recordID ?? UUID()
    _ = try BlockDocument(recordID: recordID, blocks: blocks)
    return self
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
  public var content: BlockContent?
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
    unknownFields: [String: JSONValue] = [:],
    content: BlockContent? = nil
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
    self.content = content
    self.revision = revision
  }

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
    self.init(
      id: id,
      recordID: recordID,
      position: position,
      text: text,
      revision: revision,
      parentID: parentID,
      type: type,
      orderKey: orderKey,
      attributes: attributes,
      unknownFields: unknownFields,
      content: nil
    )
  }

  public init(id: UUID, recordID: UUID, position: Int, text: String, revision: Int) {
    self.init(
      id: id, recordID: recordID, position: position, text: text, revision: revision,
      parentID: nil, type: .paragraph, orderKey: Int64(position) * 1024)
  }

  private enum CodingKeys: String, CodingKey {
    case id, recordID, parentID, type, orderKey, position, text, attributes, unknownFields, content, revision
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
      unknownFields: try container.decodeIfPresent([String: JSONValue].self, forKey: .unknownFields) ?? [:],
      content: try container.decodeIfPresent(BlockContent.self, forKey: .content)
    )
  }

  public var accessibilityDescription: String {
    if type == .task {
      let state = attributes["checked"] == "true" ? "Completed" : "Unchecked"
      return "\(state) task: \(text)"
    }
    if type == .toggle {
      return "\(isCollapsed ? "Collapsed" : "Expanded") toggle: \(text)"
    }
    if type == .callout {
      return "\(calloutStyle?.rawValue.capitalized ?? CalloutStyle.info.rawValue.capitalized) callout: \(text)"
    }
    return "\(type.accessibilityName): \(text)"
  }

  public var isCollapsed: Bool {
    type == .toggle && attributes["collapsed"] == "true"
  }

  public var calloutStyle: CalloutStyle? {
    guard type == .callout else { return nil }
    return CalloutStyle(rawValue: attributes["calloutStyle"] ?? attributes["style"] ?? "")
      ?? .info
  }
}

public struct BlockClipboard: Codable, Hashable, Sendable {
  public let blocks: [Block]

  public init(blocks: [Block]) { self.blocks = blocks }
}

public enum BlockTreeError: Error, Equatable, Sendable {
  case duplicateID(UUID)
  case missingParent(UUID)
  case missingSibling(UUID)
  case crossRecordParent(UUID)
  case cycle(UUID)
  case invalidChild(UUID)
  case invalidRange
  case cannotMerge(UUID)
  case nonTextBlock(UUID)
  case invalidClipboard
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
    }
    for block in blocks {
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

  public func creating(
    _ type: BlockType = .paragraph,
    text: String = "",
    parentID: UUID? = nil,
    before siblingID: UUID? = nil,
    id: UUID = UUID(),
    attributes: [String: String] = [:]
  ) throws -> Self {
    var attributes = attributes
    if type == .task { attributes["checked"] = attributes["checked"] ?? "false" }
    if type == .toggle { attributes["collapsed"] = attributes["collapsed"] ?? "false" }
    if type == .callout {
      attributes["calloutStyle"] = attributes["calloutStyle"] ?? attributes["style"] ?? CalloutStyle.info.rawValue
    }
    let content: BlockContent? = type == .table
      ? .table(TableContent(rows: [[TableCell()]]))
      : nil
    return try inserting(
      Block(
        id: id,
        recordID: recordID,
        position: children(of: parentID).count,
        text: type == .divider || type == .table ? "" : text,
        parentID: parentID,
        type: type,
        attributes: attributes,
        content: content),
      before: siblingID)
  }

  public func editing(id: UUID, text: String) throws -> Self {
    guard let source = block(id: id) else { throw BlockTreeError.missingParent(id) }
    guard source.type.supportsTextEditing else { throw BlockTreeError.nonTextBlock(id) }
    var copy = self
    guard let index = copy.blocks.firstIndex(where: { $0.id == id }) else {
      throw BlockTreeError.missingParent(id)
    }
    copy.blocks[index].text = text
    try copy.validate()
    return copy
  }

  public func editingTableCell(
    id: UUID,
    row: Int,
    column: Int,
    text: String
  ) throws -> Self {
    guard let source = block(id: id), source.type == .table else {
      throw BlockTreeError.invalidChild(id)
    }
    var table: TableContent
    if case .table(let content)? = source.content {
      table = content
    } else {
      table = TableContent(rows: [[TableCell()]])
    }
    guard table.setCellText(at: TableCellPosition(row: row, column: column), to: text) else {
      throw BlockTreeError.invalidRange
    }
    return try replacingContent(.table(table), for: id)
  }

  public func settingTableCellText(
    id: UUID,
    row: Int,
    column: Int,
    text: String
  ) throws -> Self {
    try editingTableCell(id: id, row: row, column: column, text: text)
  }

  public func insertingTableRow(id: UUID, at index: Int? = nil) throws -> Self {
    try updatingTable(id: id) { table in table.insertRow(at: index) }
  }

  public func removingTableRow(id: UUID, at index: Int) throws -> Self {
    try updatingTable(id: id) { table in table.removeRow(at: index) }
  }

  public func insertingTableColumn(id: UUID, at index: Int? = nil) throws -> Self {
    try updatingTable(id: id) { table in table.insertColumn(at: index) }
  }

  public func removingTableColumn(id: UUID, at index: Int) throws -> Self {
    try updatingTable(id: id) { table in table.removeColumn(at: index) }
  }

  public func settingCollapsed(_ collapsed: Bool, for id: UUID) throws -> Self {
    guard let source = block(id: id), source.type == .toggle else {
      throw BlockTreeError.invalidChild(id)
    }
    var copy = self
    guard let index = copy.blocks.firstIndex(where: { $0.id == id }) else {
      throw BlockTreeError.missingParent(id)
    }
    copy.blocks[index].attributes["collapsed"] = collapsed ? "true" : "false"
    try copy.validate()
    return copy
  }

  public func togglingCollapse(id: UUID) throws -> Self {
    guard let source = block(id: id), source.type == .toggle else {
      throw BlockTreeError.invalidChild(id)
    }
    return try settingCollapsed(!source.isCollapsed, for: id)
  }

  public func settingCalloutStyle(_ style: CalloutStyle, for id: UUID) throws -> Self {
    guard let source = block(id: id), source.type == .callout else {
      throw BlockTreeError.invalidChild(id)
    }
    var copy = self
    guard let index = copy.blocks.firstIndex(where: { $0.id == id }) else {
      throw BlockTreeError.missingParent(id)
    }
    copy.blocks[index].attributes["calloutStyle"] = style.rawValue
    try copy.validate()
    return copy
  }

  public func inserting(_ block: Block, before siblingID: UUID? = nil) throws -> Self {
    guard block.recordID == recordID else { throw BlockTreeError.crossRecordParent(block.id) }
    var copy = self
    var inserted = block
    let siblings = children(of: block.parentID)
    let index: Int
    if let siblingID {
      guard let siblingIndex = siblings.firstIndex(where: { $0.id == siblingID }) else {
        throw BlockTreeError.missingSibling(siblingID)
      }
      index = siblingIndex
    } else {
      index = siblings.count
    }
    let previous = index > 0 ? siblings[index - 1].orderKey : nil
    let next = index < siblings.count ? siblings[index].orderKey : nil
    inserted.orderKey = Self.orderKey(previous: previous, next: next)
    inserted.position = index
    copy.blocks.append(inserted)
    if let previous, let next, next - previous <= 1 {
      return try copy.reindexed(parentID: block.parentID, placing: inserted.id, at: index)
    }
    return try copy.repositioned(parentID: block.parentID)
  }

  public func moving(id: UUID, to parentID: UUID?, before siblingID: UUID? = nil) throws -> Self {
    guard let source = block(id: id) else { throw BlockTreeError.missingParent(id) }
    guard parentID != id, !descendants(of: id).contains(where: { $0.id == parentID }) else {
      throw BlockTreeError.cycle(id)
    }
    var copy = self
    copy.blocks.removeAll { $0.id == id }
    var moved = source
    moved.parentID = parentID
    let inserted = try copy.inserting(moved, before: siblingID)
    return try inserted.repositioned(parentID: source.parentID)
  }

  public func deleting(id: UUID) throws -> Self {
    guard block(id: id) != nil else { throw BlockTreeError.missingParent(id) }
    let removed = Set([id] + descendants(of: id).map(\.id))
    return try Self(recordID: recordID, blocks: blocks.filter { !removed.contains($0.id) })
  }

  public func splitting(id: UUID, atUTF16Offset offset: Int, newID: UUID = UUID()) throws -> Self {
    guard let source = block(id: id), offset >= 0 else { throw BlockTreeError.invalidRange }
    let value = source.text as NSString
    guard offset <= value.length,
      offset == 0 || offset == value.length
        || value.rangeOfComposedCharacterSequence(at: offset).location == offset
    else { throw BlockTreeError.invalidRange }
    guard !blocks.contains(where: { $0.id == newID }) else { throw BlockTreeError.duplicateID(newID) }
    var copy = self
    guard let sourceIndex = copy.blocks.firstIndex(where: { $0.id == id }) else {
      throw BlockTreeError.missingParent(id)
    }
    copy.blocks[sourceIndex].text = value.substring(with: NSRange(location: 0, length: offset))
    var right = Block(
      id: newID,
      recordID: source.recordID,
      position: source.position + 1,
      text: value.substring(from: offset),
      revision: source.revision,
      parentID: source.parentID,
      type: source.type,
      orderKey: source.orderKey,
      attributes: source.attributes,
      unknownFields: source.unknownFields,
      content: source.content
    )
    let siblings = children(of: source.parentID)
    let siblingIndex = siblings.firstIndex { $0.id == id } ?? siblings.count
    let next = siblingIndex + 1 < siblings.count ? siblings[siblingIndex + 1].id : nil
    right.orderKey = Self.orderKey(previous: source.orderKey, next: next.flatMap { block(id: $0)?.orderKey })
    right.position = source.position + 1
    copy.blocks.append(right)
    return try copy.reindexed()
  }

  public func merging(id targetID: UUID, with sourceID: UUID) throws -> Self {
    guard let target = block(id: targetID), let source = block(id: sourceID),
      targetID != sourceID, target.parentID == source.parentID,
      descendants(of: sourceID).isEmpty
    else { throw BlockTreeError.cannotMerge(sourceID) }
    let siblings = children(of: target.parentID)
    guard let targetIndex = siblings.firstIndex(where: { $0.id == targetID }),
      targetIndex + 1 < siblings.count, siblings[targetIndex + 1].id == sourceID
    else { throw BlockTreeError.cannotMerge(sourceID) }
    var copy = self
    guard let index = copy.blocks.firstIndex(where: { $0.id == targetID }) else {
      throw BlockTreeError.missingParent(targetID)
    }
    copy.blocks[index].text += source.text
    copy.blocks.removeAll { $0.id == sourceID }
    return try copy.reindexed()
  }

  public func indenting(id: UUID, under parentID: UUID) throws -> Self {
    guard let parent = block(id: parentID), parent.type.acceptsChildren else {
      throw BlockTreeError.invalidChild(id)
    }
    return try moving(id: id, to: parentID)
  }

  public func outdenting(id: UUID) throws -> Self {
    guard let source = block(id: id), let parentID = source.parentID,
      let parent = block(id: parentID)
    else { return self }
    return try moving(id: id, to: parent.parentID)
  }

  public func settingType(_ type: BlockType, for id: UUID) throws -> Self {
    guard let source = block(id: id) else { throw BlockTreeError.missingParent(id) }
    if !type.acceptsChildren && !descendants(of: id).isEmpty {
      throw BlockTreeError.invalidChild(id)
    }
    var copy = self
    guard let index = copy.blocks.firstIndex(where: { $0.id == id }) else {
      throw BlockTreeError.missingParent(id)
    }
    copy.blocks[index].type = type
    if type == .task {
      copy.blocks[index].attributes["checked"] = source.attributes["checked"] ?? "false"
    } else {
      copy.blocks[index].attributes.removeValue(forKey: "checked")
    }
    if type == .toggle {
      copy.blocks[index].attributes["collapsed"] = source.attributes["collapsed"] ?? "false"
    } else {
      copy.blocks[index].attributes.removeValue(forKey: "collapsed")
    }
    if type == .callout {
      copy.blocks[index].attributes["calloutStyle"] = source.attributes["calloutStyle"]
        ?? source.attributes["style"] ?? CalloutStyle.info.rawValue
    }
    if type == .divider { copy.blocks[index].text = "" }
    if type == .table {
      if case .table? = copy.blocks[index].content { }
      else { copy.blocks[index].content = .table(TableContent(rows: [[TableCell()]])) }
    }
    return try copy.reindexed()
  }

  public func togglingTask(id: UUID) throws -> Self {
    guard let source = block(id: id), source.type == .task else {
      throw BlockTreeError.invalidChild(id)
    }
    var copy = self
    guard let index = copy.blocks.firstIndex(where: { $0.id == id }) else {
      throw BlockTreeError.missingParent(id)
    }
    copy.blocks[index].attributes["checked"] = source.attributes["checked"] == "true" ? "false" : "true"
    return copy
  }

  public func listNumber(for id: UUID) -> Int? {
    guard let source = block(id: id), source.type == .numberedList else { return nil }
    let siblings = children(of: source.parentID)
    guard let index = siblings.firstIndex(where: { $0.id == id }) else { return nil }
    var number = 0
    for sibling in siblings[...index] {
      if sibling.type == .numberedList {
        number += 1
      } else {
        number = 0
      }
    }
    return number == 0 ? nil : number
  }

  public func copying(ids: [UUID]) throws -> BlockClipboard {
    guard !ids.isEmpty else { return BlockClipboard(blocks: []) }
    let selected = Set(ids)
    guard selected.count == ids.count, ids.allSatisfy({ block(id: $0) != nil }) else {
      throw BlockTreeError.invalidClipboard
    }
    let roots = linearizedBlocks().filter { block in
      selected.contains(block.id) && (block.parentID == nil || !selected.contains(block.parentID!))
    }
    let copied = roots.flatMap { subtree(of: $0.id) }
    return BlockClipboard(blocks: copied)
  }

  public func pasting(
    _ clipboard: BlockClipboard,
    into parentID: UUID? = nil,
    before siblingID: UUID? = nil,
    idGenerator: any IDGenerator = UUIDGenerator()
  ) throws -> Self {
    guard !clipboard.blocks.isEmpty else { return self }
    if let parentID {
      guard let parent = block(id: parentID), parent.type.acceptsChildren else {
        throw BlockTreeError.invalidChild(parentID)
      }
    }
    if let siblingID {
      guard let sibling = block(id: siblingID), sibling.parentID == parentID else {
        throw BlockTreeError.missingSibling(siblingID)
      }
    }
    let sourceIDs = clipboard.blocks.map(\.id)
    guard Set(sourceIDs).count == sourceIDs.count else { throw BlockTreeError.invalidClipboard }
    let sourceIDSet = Set(sourceIDs)
    let roots = clipboard.blocks.filter {
      $0.parentID == nil || !sourceIDSet.contains($0.parentID!)
    }
    guard roots.count > 0 else { throw BlockTreeError.invalidClipboard }
    var remap: [UUID: UUID] = [:]
    for sourceID in sourceIDs {
      let targetID = idGenerator.next()
      guard !remap.values.contains(targetID), block(id: targetID) == nil else {
        throw BlockTreeError.duplicateID(targetID)
      }
      remap[sourceID] = targetID
    }

    var result = self
    for source in clipboard.blocks {
      let isRoot = source.parentID == nil || !sourceIDSet.contains(source.parentID!)
      let targetParent = isRoot ? parentID : remap[source.parentID!]
      guard isRoot || targetParent != nil else { throw BlockTreeError.invalidClipboard }
      let copied = Block(
        id: remap[source.id]!,
        recordID: recordID,
        position: result.children(of: targetParent).count,
        text: source.text,
        revision: 0,
        parentID: targetParent,
        type: source.type,
        orderKey: source.orderKey,
        attributes: source.attributes,
        unknownFields: source.unknownFields,
        content: source.content)
      result = try result.inserting(copied, before: isRoot ? siblingID : nil)
    }
    return result
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

  private func linearizedBlocks() -> [Block] {
    func visit(_ parentID: UUID?) -> [Block] {
      children(of: parentID).flatMap { block in [block] + visit(block.id) }
    }
    return visit(nil)
  }

  private func subtree(of id: UUID) -> [Block] {
    guard let root = block(id: id) else { return [] }
    func visit(_ parentID: UUID) -> [Block] {
      children(of: parentID).flatMap { block in [block] + visit(block.id) }
    }
    return [root] + visit(id)
  }

  private func replacingContent(_ content: BlockContent, for id: UUID) throws -> Self {
    var copy = self
    guard let index = copy.blocks.firstIndex(where: { $0.id == id }) else {
      throw BlockTreeError.missingParent(id)
    }
    copy.blocks[index].content = content
    try copy.validate()
    return copy
  }

  private func updatingTable(
    id: UUID,
    _ update: (inout TableContent) -> Void
  ) throws -> Self {
    guard let source = block(id: id), source.type == .table else {
      throw BlockTreeError.invalidChild(id)
    }
    var table: TableContent
    if case .table(let content)? = source.content {
      table = content
    } else {
      table = TableContent(rows: [[TableCell()]])
    }
    update(&table)
    return try replacingContent(.table(table), for: id)
  }

  private static func orderKey(previous: Int64?, next: Int64?) -> Int64 {
    switch (previous, next) {
    case let (left?, right?) where right - left > 1: return left + (right - left) / 2
    case let (left?, nil): return left + 1024
    case let (nil, right?): return right - 1024
    default: return 0
    }
  }

  private func repositioned(parentID: UUID?) throws -> Self {
    var copy = self
    let ordered = copy.children(of: parentID)
    for (index, sibling) in ordered.enumerated() {
      guard let blockIndex = copy.blocks.firstIndex(where: { $0.id == sibling.id }) else { continue }
      copy.blocks[blockIndex].position = index
    }
    try copy.validate()
    return copy
  }

  private func reindexed(parentID: UUID?) throws -> Self {
    var copy = self
    let ordered = copy.children(of: parentID)
    for (index, sibling) in ordered.enumerated() {
      guard let blockIndex = copy.blocks.firstIndex(where: { $0.id == sibling.id }) else { continue }
      copy.blocks[blockIndex].position = index
      copy.blocks[blockIndex].orderKey = Int64(index) * 1024
    }
    try copy.validate()
    return copy
  }

  private func reindexed(parentID: UUID?, placing insertedID: UUID, at index: Int) throws -> Self {
    var copy = self
    var orderedIDs = copy.children(of: parentID).map(\.id)
    orderedIDs.removeAll { $0 == insertedID }
    orderedIDs.insert(insertedID, at: min(max(index, 0), orderedIDs.count))
    for (position, id) in orderedIDs.enumerated() {
      guard let blockIndex = copy.blocks.firstIndex(where: { $0.id == id }) else { continue }
      copy.blocks[blockIndex].position = position
      copy.blocks[blockIndex].orderKey = Int64(position) * 1024
    }
    try copy.validate()
    return copy
  }

  private func reindexed() throws -> Self {
    var copy = self
    let parentIDs = Set(copy.blocks.map(\.parentID))
    for parentID in parentIDs { copy = try copy.reindexed(parentID: parentID) }
    return copy
  }
}

public struct Asset: Codable, Hashable, Sendable {
  public let id: UUID
  public let contentHash: String
  public let byteCount: Int64
  public let mediaType: String?
  public let originalFilename: String?

  public init(
    id: UUID,
    contentHash: String,
    byteCount: Int64,
    mediaType: String? = nil,
    originalFilename: String? = nil
  ) {
    self.id = id
    self.contentHash = contentHash
    self.byteCount = byteCount
    self.mediaType = mediaType
    self.originalFilename = originalFilename
  }

  public init(id: UUID, contentHash: String, byteCount: Int64) {
    self.init(id: id, contentHash: contentHash, byteCount: byteCount, mediaType: nil, originalFilename: nil)
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
