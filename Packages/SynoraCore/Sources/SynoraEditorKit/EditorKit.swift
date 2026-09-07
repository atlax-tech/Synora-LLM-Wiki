import Foundation
import SynoraDomain

public struct BlockTextRange: Hashable, Sendable {
  public let blockID: UUID
  public let range: NSRange

  public init(blockID: UUID, range: NSRange) {
    self.blockID = blockID
    self.range = range
  }
}

public struct TextStorageAdapter: Sendable {
  public let document: BlockDocument
  public let text: String
  public let ranges: [BlockTextRange]

  public init(document: BlockDocument) {
    self.document = document
    var value = ""
    var mapped: [BlockTextRange] = []
    for (index, block) in Self.linearizedBlocks(document).enumerated() {
      if index > 0 { value.append("\n") }
      let start = (value as NSString).length
      value.append(block.text)
      mapped.append(BlockTextRange(
        blockID: block.id, range: NSRange(location: start, length: (block.text as NSString).length)))
    }
    text = value
    ranges = mapped
  }

  public func applying(range: NSRange, replacement: String, marked: Bool = false) throws
    -> BlockDocument
  {
    let source = text as NSString
    guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= source.length,
      Self.isComposedBoundary(range.location, in: source),
      Self.isComposedBoundary(NSMaxRange(range), in: source)
    else { throw EditorError.invalidSelection }
    guard !marked else { return document }
    let blocks = Self.linearizedBlocks(document)
    guard !blocks.isEmpty else {
      let block = Block(id: UUID(), recordID: document.recordID, position: 0, text: replacement)
      return try BlockDocument(recordID: document.recordID, blocks: [block])
    }
    guard let startIndex = index(containing: range.location, preferPrevious: true),
      let endIndex = index(containing: NSMaxRange(range), preferPrevious: true)
    else { throw EditorError.invalidSelection }
    guard blocks[startIndex].type.supportsTextEditing,
      blocks[endIndex].type.supportsTextEditing else { throw EditorError.invalidSelection }

    let startRange = ranges[startIndex].range
    let endRange = ranges[endIndex].range
    let startText = blocks[startIndex].text as NSString
    let endText = blocks[endIndex].text as NSString
    let startOffset = min(max(range.location - startRange.location, 0), startText.length)
    let endOffset = min(max(NSMaxRange(range) - endRange.location, 0), endText.length)
    let prefix = startText.substring(with: NSRange(location: 0, length: startOffset))
    let suffix = endText.substring(from: endOffset)
    let pieces = replacement.components(separatedBy: "\n")
    var updated: [Block] = []
    var first = blocks[startIndex]
    first.text = prefix + (pieces.first ?? "") + (pieces.count == 1 ? suffix : "")
    updated.append(first)
    if pieces.count > 1 {
      for piece in pieces.dropFirst().dropLast() {
        updated.append(Block(
          id: UUID(), recordID: document.recordID, position: updated.count, text: piece,
          type: first.type, attributes: first.attributes, unknownFields: first.unknownFields,
          content: first.content))
      }
      let lastID = endIndex == startIndex ? UUID() : blocks[endIndex].id
      let last = Block(
        id: lastID,
        recordID: blocks[endIndex].recordID,
        position: updated.count,
        text: (pieces.last ?? "") + suffix,
        revision: blocks[endIndex].revision,
        parentID: blocks[endIndex].parentID,
        type: blocks[endIndex].type,
        orderKey: blocks[endIndex].orderKey,
        attributes: blocks[endIndex].attributes,
        unknownFields: blocks[endIndex].unknownFields,
        content: blocks[endIndex].content
      )
      updated.append(last)
    }
    var removedIDs = Set(blocks[startIndex...endIndex].map(\.id))
    for block in blocks[startIndex...endIndex] {
      removedIDs.formUnion(document.descendants(of: block.id).map(\.id))
    }
    let untouched = blocks.enumerated().compactMap { index, block in
      removedIDs.contains(block.id) ? nil : block
    }
    let insertionIndex = blocks.firstIndex { $0.id == blocks[startIndex].id } ?? 0
    var result = Array(untouched.prefix(insertionIndex)) + updated
    result += untouched.dropFirst(insertionIndex)
    return try BlockDocument(recordID: document.recordID, blocks: result)
  }

  private func index(containing offset: Int, preferPrevious: Bool) -> Int? {
    guard !ranges.isEmpty else { return nil }
    for index in ranges.indices {
      let range = ranges[index].range
      if offset < NSMaxRange(range) || (preferPrevious && offset == NSMaxRange(range)) {
        return index
      }
      if index + 1 < ranges.count, offset < ranges[index + 1].range.location {
        return index
      }
    }
    return offset == (text as NSString).length ? ranges.count - 1 : nil
  }

  private static func linearizedBlocks(_ document: BlockDocument) -> [Block] {
    func visit(_ parentID: UUID?, hidden: Bool = false) -> [Block] {
      guard !hidden else { return [] }
      return document.children(of: parentID).flatMap { block in
        [block] + visit(block.id, hidden: block.isCollapsed)
      }
    }
    return visit(nil)
  }

  private static func isComposedBoundary(_ offset: Int, in source: NSString) -> Bool {
    guard offset > 0, offset < source.length else { return true }
    let range = source.rangeOfComposedCharacterSequence(at: offset)
    return range.location == offset || NSMaxRange(range) == offset
  }
}

public struct EditorFocus: Hashable, Sendable {
  public let blockID: UUID
  public let utf16Offset: Int
  public let tableCell: TableCellPosition?

  public init(blockID: UUID, utf16Offset: Int = 0, tableCell: TableCellPosition? = nil) {
    self.blockID = blockID
    self.utf16Offset = utf16Offset
    self.tableCell = tableCell
  }
}

public enum EditorCommand: Hashable, Sendable {
  case insertText(String)
  case setBlockType(BlockType)
  case toggleTask
  case deleteBlock
  case splitBlock(atUTF16Offset: Int, newID: UUID)
  case mergeWithNext
  case indent
  case outdent
  case editTableCell(row: Int, column: Int, text: String)
  case insertTableRow(at: Int?)
  case removeTableRow(at: Int)
  case insertTableColumn(at: Int?)
  case removeTableColumn(at: Int)
  case toggleCollapse
  case setCalloutStyle(CalloutStyle)
}

public enum EditorError: Error, Equatable, Sendable {
  case invalidSelection
  case unsupportedCommand
  case noUndo
  case noRedo
}

public struct EditorSession: Sendable {
  public private(set) var document: BlockDocument
  public private(set) var focus: EditorFocus?

  private struct Snapshot: Sendable {
    let document: BlockDocument
    let focus: EditorFocus?
    let collapsedFocus: [UUID: EditorFocus]
  }

  private var collapsedFocus: [UUID: EditorFocus] = [:]
  private var undoStack: [Snapshot] = []
  private var redoStack: [Snapshot] = []

  public init(document: BlockDocument) {
    self.document = document
    focus = nil
  }

  public var focusedBlockID: UUID? { focus?.blockID }

  public mutating func focus(on blockID: UUID, atUTF16Offset offset: Int = 0) throws {
    guard let block = document.block(id: blockID), offset >= 0 else {
      throw EditorError.invalidSelection
    }
    let value = block.text as NSString
    guard offset <= value.length, Self.isComposedBoundary(offset, in: value) else {
      throw EditorError.invalidSelection
    }
    focus = EditorFocus(blockID: blockID, utf16Offset: offset)
  }

  public mutating func focus(in blockID: UUID, cell position: TableCellPosition) throws {
    guard let block = document.block(id: blockID), block.type == .table,
      case .table(let table)? = block.content, table.cell(at: position) != nil else {
      throw EditorError.invalidSelection
    }
    focus = EditorFocus(blockID: blockID, tableCell: position)
  }

  public func tableCell(in blockID: UUID, row: Int, column: Int) -> TableCell? {
    guard let block = document.block(id: blockID), case .table(let table)? = block.content else {
      return nil
    }
    return table.cell(atRow: row, column: column)
  }

  @discardableResult
  public mutating func navigateTable(
    in blockID: UUID,
    from position: TableCellPosition,
    direction: TableNavigationDirection
  ) throws -> TableCellPosition? {
    guard let block = document.block(id: blockID), block.type == .table,
      case .table(let table)? = block.content else {
      throw EditorError.invalidSelection
    }
    guard let next = table.navigating(from: position, direction: direction) else { return nil }
    focus = EditorFocus(blockID: blockID, tableCell: next)
    return next
  }

  @discardableResult
  public mutating func pressTab(
    in blockID: UUID,
    from position: TableCellPosition
  ) throws -> TableCellPosition? {
    if let next = try navigateTable(in: blockID, from: position, direction: .next) {
      return next
    }
    guard let block = document.block(id: blockID), case .table(let table)? = block.content,
      !table.rows.isEmpty, position.row == table.rows.count - 1,
      position.column == table.columnCount - 1 else { return nil }
    let next = try document.insertingTableRow(id: blockID)
    let target = TableCellPosition(row: table.rows.count, column: 0)
    _ = commit(next, focus: EditorFocus(blockID: blockID, tableCell: target))
    return target
  }

  @discardableResult
  public mutating func apply(range: NSRange, replacement: String, marked: Bool = false) throws
    -> BlockDocument
  {
    guard !marked else { return document }
    let next = try TextStorageAdapter(document: document).applying(
      range: range, replacement: replacement)
    return commit(next)
  }

  @discardableResult
  public mutating func execute(_ command: EditorCommand, blockID: UUID) throws -> BlockDocument {
    let next: BlockDocument
    var focusAfter: EditorFocus?
    var collapsedFocusAfter: [UUID: EditorFocus]?
    switch command {
    case .insertText(let text):
      let adapter = TextStorageAdapter(document: document)
      guard let range = adapter.ranges.first(where: { $0.blockID == blockID })?.range else {
        throw EditorError.invalidSelection
      }
      next = try adapter.applying(
        range: NSRange(location: NSMaxRange(range), length: 0), replacement: text)
    case .setBlockType(let type):
      next = try document.settingType(type, for: blockID)
    case .toggleTask:
      next = try document.togglingTask(id: blockID)
    case .deleteBlock:
      next = try document.deleting(id: blockID)
    case .splitBlock(let offset, let newID):
      next = try document.splitting(id: blockID, atUTF16Offset: offset, newID: newID)
    case .mergeWithNext:
      let siblings = document.children(of: document.block(id: blockID)?.parentID)
      guard let index = siblings.firstIndex(where: { $0.id == blockID }), index + 1 < siblings.count else {
        throw EditorError.invalidSelection
      }
      next = try document.merging(id: blockID, with: siblings[index + 1].id)
    case .indent:
      let siblings = document.children(of: document.block(id: blockID)?.parentID)
      guard let index = siblings.firstIndex(where: { $0.id == blockID }), index > 0 else {
        throw EditorError.invalidSelection
      }
      next = try document.indenting(id: blockID, under: siblings[index - 1].id)
    case .outdent:
      next = try document.outdenting(id: blockID)
    case .editTableCell(let row, let column, let text):
      next = try document.editingTableCell(id: blockID, row: row, column: column, text: text)
      focusAfter = EditorFocus(
        blockID: blockID, tableCell: TableCellPosition(row: row, column: column))
    case .insertTableRow(let index):
      next = try document.insertingTableRow(id: blockID, at: index)
    case .removeTableRow(let index):
      next = try document.removingTableRow(id: blockID, at: index)
    case .insertTableColumn(let index):
      next = try document.insertingTableColumn(id: blockID, at: index)
    case .removeTableColumn(let index):
      next = try document.removingTableColumn(id: blockID, at: index)
    case .toggleCollapse:
      guard let source = document.block(id: blockID), source.type == .toggle else {
        throw EditorError.invalidSelection
      }
      let collapsing = !source.isCollapsed
      var saved = collapsedFocus
      if collapsing, let current = focus,
        document.descendants(of: blockID).contains(where: { $0.id == current.blockID }) {
        saved[blockID] = current
        focusAfter = EditorFocus(blockID: blockID, utf16Offset: source.text.utf16.count)
      } else if !collapsing, let restored = saved.removeValue(forKey: blockID),
        document.block(id: restored.blockID) != nil {
        focusAfter = restored
      }
      collapsedFocusAfter = saved
      next = try document.togglingCollapse(id: blockID)
    case .setCalloutStyle(let style):
      next = try document.settingCalloutStyle(style, for: blockID)
    }
    return commit(next, focus: focusAfter, collapsedFocus: collapsedFocusAfter)
  }

  @discardableResult
  public mutating func pressReturn(
    in blockID: UUID,
    atUTF16Offset offset: Int,
    newID: UUID = UUID()
  ) throws -> BlockDocument {
    guard let block = document.block(id: blockID),
      block.type.supportsTextEditing || block.type == .divider else {
      throw EditorError.invalidSelection
    }
    if block.type == .divider {
      guard offset == 0 else { throw EditorError.invalidSelection }
      let siblings = document.children(of: block.parentID)
      guard let index = siblings.firstIndex(where: { $0.id == blockID }) else {
        throw EditorError.invalidSelection
      }
      let nextID = index + 1 < siblings.count ? siblings[index + 1].id : nil
      return commit(try document.creating(
        .paragraph, parentID: block.parentID, before: nextID, id: newID))
    }
    if block.type.isList && block.text.isEmpty && document.descendants(of: blockID).isEmpty {
      guard offset == 0 else { throw EditorError.invalidSelection }
      return commit(try document.settingType(.paragraph, for: blockID))
    }
    return commit(try document.splitting(id: blockID, atUTF16Offset: offset, newID: newID))
  }

  @discardableResult
  public mutating func pressBackspace(
    in blockID: UUID,
    atUTF16Offset offset: Int
  ) throws -> BlockDocument {
    guard let block = document.block(id: blockID), offset >= 0 else {
      throw EditorError.invalidSelection
    }
    let value = block.text as NSString
    guard offset <= value.length else { throw EditorError.invalidSelection }
    if offset == 0 {
      if block.type.isList && block.text.isEmpty {
        return commit(try document.settingType(.paragraph, for: blockID))
      }
      if block.type == .divider { return commit(try document.deleting(id: blockID)) }
      let siblings = document.children(of: block.parentID)
      guard let index = siblings.firstIndex(where: { $0.id == blockID }), index > 0 else {
        return document
      }
      return commit(try document.merging(id: siblings[index - 1].id, with: blockID))
    }
    if offset < value.length {
      let boundary = value.rangeOfComposedCharacterSequence(at: offset)
      guard boundary.location == offset || NSMaxRange(boundary) == offset else {
        throw EditorError.invalidSelection
      }
    }
    let previous = value.rangeOfComposedCharacterSequence(at: offset - 1)
    guard let mapped = TextStorageAdapter(document: document).ranges.first(where: { $0.blockID == blockID }) else {
      throw EditorError.invalidSelection
    }
    let next = try TextStorageAdapter(document: document).applying(
      range: NSRange(location: mapped.range.location + previous.location, length: previous.length),
      replacement: "")
    return commit(next)
  }

  public func copy(blockIDs: [UUID]) throws -> BlockClipboard {
    try document.copying(ids: blockIDs)
  }

  @discardableResult
  public mutating func paste(
    _ clipboard: BlockClipboard,
    into parentID: UUID? = nil,
    before siblingID: UUID? = nil,
    idGenerator: any IDGenerator = UUIDGenerator()
  ) throws -> BlockDocument {
    commit(try document.pasting(
      clipboard,
      into: parentID,
      before: siblingID,
      idGenerator: idGenerator))
  }

  @discardableResult
  public mutating func editTableCell(
    in blockID: UUID,
    row: Int,
    column: Int,
    text: String
  ) throws -> BlockDocument {
    try execute(.editTableCell(row: row, column: column, text: text), blockID: blockID)
  }

  @discardableResult
  public mutating func toggleCollapse(in blockID: UUID) throws -> BlockDocument {
    try execute(.toggleCollapse, blockID: blockID)
  }

  @discardableResult
  public mutating func setCalloutStyle(
    _ style: CalloutStyle,
    in blockID: UUID
  ) throws -> BlockDocument {
    try execute(.setCalloutStyle(style), blockID: blockID)
  }

  @discardableResult
  public mutating func applyMarkdownShortcut(
    in blockID: UUID,
    inCodeBlock: Bool = false,
    markedText: Bool = false
  ) throws -> BlockDocument {
    guard let source = document.block(id: blockID) else {
      throw EditorError.invalidSelection
    }
    guard let shortcut = MarkdownShortcut.block(
      for: source.text,
      inCodeBlock: inCodeBlock || source.type == .code,
      markedText: markedText) else { return document }
    var next = try document.settingType(shortcut.type, for: blockID)
    if shortcut.type.supportsTextEditing {
      next = try next.editing(id: blockID, text: shortcut.text)
    }
    if shortcut.type == .task, let checked = MarkdownShortcut.taskChecked(for: source.text) {
      next = try next.settingTaskChecked(checked, for: blockID)
    }
    return commit(next)
  }

  @discardableResult
  public mutating func applySlashCommand(
    _ command: SlashCommand,
    in blockID: UUID,
    clearTrigger: Bool = true
  ) throws -> BlockDocument {
    guard let source = document.block(id: blockID) else {
      throw EditorError.invalidSelection
    }
    var next = try document.settingType(command.blockType, for: blockID)
    if clearTrigger,
      source.text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") {
      next = try next.settingText("", for: blockID)
    }
    return commit(next)
  }

  @discardableResult
  public mutating func insertReference(
    _ target: ReferenceCandidate,
    in blockID: UUID,
    atUTF16Offset offset: Int,
    syntax: ReferenceSyntax = .wikiLink
  ) throws -> BlockDocument {
    guard let block = document.block(id: blockID), block.type.supportsTextEditing else {
      throw EditorError.invalidSelection
    }
    let value = block.text as NSString
    guard offset >= 0, offset <= value.length, Self.isComposedBoundary(offset, in: value),
      let mapped = TextStorageAdapter(document: document).ranges.first(where: { $0.blockID == blockID })
    else { throw EditorError.invalidSelection }
    let token = target.token(using: syntax)
    let next = try TextStorageAdapter(document: document).applying(
      range: NSRange(location: mapped.range.location + offset, length: 0),
      replacement: token)
    return commit(next, focus: EditorFocus(
      blockID: blockID,
      utf16Offset: offset + (token as NSString).length))
  }

  @discardableResult
  public mutating func insertReference(
    targetID: UUID,
    in blockID: UUID,
    atUTF16Offset offset: Int,
    syntax: ReferenceSyntax = .wikiLink
  ) throws -> BlockDocument {
    try insertReference(
      ReferenceCandidate(id: targetID, title: "", kind: .record),
      in: blockID,
      atUTF16Offset: offset,
      syntax: syntax)
  }

  private mutating func commit(
    _ next: BlockDocument,
    focus override: EditorFocus? = nil,
    collapsedFocus map: [UUID: EditorFocus]? = nil
  ) -> BlockDocument {
    guard next != document else {
      if let override { focus = resolved(override, in: document) }
      if let map { collapsedFocus = map }
      return document
    }
    undoStack.append(Snapshot(
      document: document, focus: focus, collapsedFocus: collapsedFocus))
    redoStack.removeAll()
    document = next
    if let override { focus = resolved(override, in: next) }
    else { focus = resolved(focus, in: next) }
    if let map { collapsedFocus = map }
    collapsedFocus = collapsedFocus.filter {
      next.block(id: $0.key) != nil && next.block(id: $0.value.blockID) != nil
    }
    return next
  }

  public mutating func undo() throws -> BlockDocument {
    guard let previous = undoStack.popLast() else { throw EditorError.noUndo }
    redoStack.append(Snapshot(
      document: document, focus: focus, collapsedFocus: collapsedFocus))
    document = previous.document
    focus = resolved(previous.focus, in: document)
    collapsedFocus = previous.collapsedFocus.filter {
      document.block(id: $0.key) != nil && document.block(id: $0.value.blockID) != nil
    }
    return document
  }

  public mutating func redo() throws -> BlockDocument {
    guard let next = redoStack.popLast() else { throw EditorError.noRedo }
    undoStack.append(Snapshot(
      document: document, focus: focus, collapsedFocus: collapsedFocus))
    document = next.document
    focus = resolved(next.focus, in: document)
    collapsedFocus = next.collapsedFocus.filter {
      document.block(id: $0.key) != nil && document.block(id: $0.value.blockID) != nil
    }
    return document
  }

  private func resolved(_ candidate: EditorFocus?, in document: BlockDocument) -> EditorFocus? {
    guard let candidate, let block = document.block(id: candidate.blockID) else { return nil }
    if let cell = candidate.tableCell {
      guard case .table(let table)? = block.content, table.cell(at: cell) != nil else {
        return nil
      }
      return candidate
    }
    let value = block.text as NSString
    guard candidate.utf16Offset >= 0, candidate.utf16Offset <= value.length,
      Self.isComposedBoundary(candidate.utf16Offset, in: value) else { return nil }
    return candidate
  }

  private static func isComposedBoundary(_ offset: Int, in source: NSString) -> Bool {
    guard offset > 0, offset < source.length else { return true }
    let range = source.rangeOfComposedCharacterSequence(at: offset)
    return range.location == offset || NSMaxRange(range) == offset
  }
}

public enum MarkdownShortcut {
  public static func block(
    for line: String,
    inCodeBlock: Bool = false,
    markedText: Bool = false
  ) -> (type: BlockType, text: String)? {
    guard !isDisabled(inCodeBlock: inCodeBlock, markedText: markedText) else { return nil }
    if line == "---" { return (.divider, "") }
    let shortcuts: [(String, BlockType)] = [
      ("### ", .heading3), ("## ", .heading2), ("# ", .heading1),
      ("- [ ] ", .task), ("- [x] ", .task), ("- [X] ", .task),
      ("- ", .bulletedList), ("> ", .quote),
    ]
    if let match = shortcuts.first(where: { line.hasPrefix($0.0) }) {
      return (match.1, String(line.dropFirst(match.0.count)))
    }
    if let dot = line.firstIndex(of: "."),
      line[..<dot].allSatisfy(\.isNumber), line[line.index(after: dot)...].hasPrefix(" ")
    {
      return (.numberedList, String(line[line.index(dot, offsetBy: 2)...]))
    }
    if line.hasPrefix("```") { return (.code, String(line.dropFirst(3))) }
    return nil
  }

  public static func taskChecked(for line: String) -> Bool? {
    if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") { return true }
    if line.hasPrefix("- [ ] ") { return false }
    return nil
  }

  public static func isDisabled(inCodeBlock: Bool, markedText: Bool) -> Bool {
    inCodeBlock || markedText
  }
}

public enum SlashCommand: String, CaseIterable, Hashable, Sendable {
  case paragraph, heading1, heading2, heading3, bulletedList, numberedList, task
  case quote, code, divider, table, toggle, callout, image, gallery, video, audio, pdf, file, link

  public static var availableCommands: [Self] {
    [.paragraph, .heading1, .heading2, .heading3, .bulletedList, .numberedList, .task,
      .quote, .code, .divider, .table, .toggle, .callout]
  }

  public var blockType: BlockType {
    switch self {
    case .paragraph: .paragraph
    case .heading1: .heading1
    case .heading2: .heading2
    case .heading3: .heading3
    case .bulletedList: .bulletedList
    case .numberedList: .numberedList
    case .task: .task
    case .quote: .quote
    case .code: .code
    case .divider: .divider
    case .table: .table
    case .toggle: .toggle
    case .callout: .callout
    case .image: .image
    case .gallery: .gallery
    case .video: .video
    case .audio: .audio
    case .pdf: .pdf
    case .file: .file
    case .link: .link
    }
  }

  public var title: String {
    switch self {
    case .heading1: "Heading 1"
    case .heading2: "Heading 2"
    case .heading3: "Heading 3"
    case .bulletedList: "Bulleted list"
    case .numberedList: "Numbered list"
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
    case .paragraph: "Paragraph"
    }
  }

  public var aliases: [String] {
    switch self {
    case .paragraph: ["text", "正文", "段落"]
    case .heading1: ["标题", "一级标题", "h1"]
    case .heading2: ["标题", "二级标题", "h2"]
    case .heading3: ["标题", "三级标题", "h3"]
    case .bulletedList: ["无序列表", "项目符号", "bullet"]
    case .numberedList: ["有序列表", "编号列表", "number"]
    case .task: ["待办", "任务", "todo", "checkbox"]
    case .quote: ["引用", "blockquote"]
    case .code: ["代码", "代码块", "fenced code"]
    case .divider: ["分隔线", "水平线", "rule"]
    case .table: ["表格"]
    case .toggle: ["折叠", "折叠块"]
    case .callout: ["提示", "高亮"]
    case .image: ["图片"]
    case .gallery: ["画廊", "拼贴"]
    case .video: ["视频"]
    case .audio: ["音频"]
    case .pdf: ["文档"]
    case .file: ["文件"]
    case .link: ["链接"]
    }
  }

  public static func matching(_ query: String) -> [Self] {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
      .drop(while: { $0 == "/" }).lowercased()
    guard !normalized.isEmpty else { return allCases }
    return allCases.filter {
      $0.rawValue.localizedCaseInsensitiveContains(normalized)
        || $0.title.localizedCaseInsensitiveContains(normalized)
        || $0.aliases.contains { $0.localizedCaseInsensitiveContains(normalized) }
    }
  }
}

public enum SlashMenuKey: Hashable, Sendable {
  case up
  case down
  case enter
  case escape

  public static var returnKey: Self { .enter }
  public static var esc: Self { .escape }
}

public enum SlashMenuAction: Hashable, Sendable {
  case none
  case selected(SlashCommand)
  case cancelled
}

public struct SlashMenuState: Hashable, Sendable {
  public private(set) var query: String
  public private(set) var candidates: [SlashCommand]
  public private(set) var selectedIndex: Int?
  public private(set) var isPresented: Bool
  private let commands: [SlashCommand]

  public init(query: String = "", commands: [SlashCommand] = SlashCommand.availableCommands) {
    self.query = Self.normalizedQuery(query)
    self.commands = commands
    candidates = Self.filtered(self.query, commands: commands)
    selectedIndex = candidates.isEmpty ? nil : 0
    isPresented = true
  }

  public mutating func update(query: String) {
    self.query = Self.normalizedQuery(query)
    candidates = Self.filtered(self.query, commands: commands)
    selectedIndex = candidates.isEmpty ? nil : 0
  }

  @discardableResult
  public mutating func moveSelection(by delta: Int) -> Int? {
    guard !candidates.isEmpty else {
      selectedIndex = nil
      return nil
    }
    let current = selectedIndex ?? 0
    selectedIndex = (current + delta % candidates.count + candidates.count) % candidates.count
    return selectedIndex
  }

  public mutating func handle(_ key: SlashMenuKey) -> SlashMenuAction {
    guard isPresented else { return .none }
    switch key {
    case .up:
      _ = moveSelection(by: -1)
      return .none
    case .down:
      _ = moveSelection(by: 1)
      return .none
    case .enter:
      guard let selectedIndex else { return .none }
      isPresented = false
      return .selected(candidates[selectedIndex])
    case .escape:
      isPresented = false
      return .cancelled
    }
  }

  public mutating func cancel() {
    isPresented = false
  }

  private static func normalizedQuery(_ query: String) -> String {
    query.trimmingCharacters(in: .whitespacesAndNewlines).drop { $0 == "/" }.description
  }

  private static func filtered(_ query: String, commands: [SlashCommand]) -> [SlashCommand] {
    guard !query.isEmpty else { return commands }
    return commands.filter { command in
      command.rawValue.localizedCaseInsensitiveContains(query)
        || command.title.localizedCaseInsensitiveContains(query)
        || command.aliases.contains { $0.localizedCaseInsensitiveContains(query) }
    }
  }
}

public enum ReferenceSyntax: String, Codable, Hashable, Sendable {
  case wikiLink
  case mention

  public static var wikilink: Self { .wikiLink }
}

public enum ReferenceTargetKind: String, Codable, Hashable, Sendable {
  case record
  case block
}

public struct ReferenceCandidate: Hashable, Sendable {
  public let id: UUID
  public let title: String
  public let kind: ReferenceTargetKind

  public init(id: UUID, title: String, kind: ReferenceTargetKind) {
    self.id = id
    self.title = title
    self.kind = kind
  }

  public func token(using syntax: ReferenceSyntax = .wikiLink) -> String {
    switch syntax {
    case .wikiLink: "[[\(id.uuidString)]]"
    case .mention: "@[\(id.uuidString)]"
    }
  }
}

public struct RecordReference: Hashable, Sendable {
  public let targetID: UUID
  public let range: NSRange
  public let syntax: ReferenceSyntax

  public init(targetID: UUID, range: NSRange, syntax: ReferenceSyntax = .wikiLink) {
    self.targetID = targetID
    self.range = range
    self.syntax = syntax
  }
}

public enum ReferenceParser {
  public static func candidates(
    for query: String,
    records: [Record],
    blocks: [Block] = []
  ) -> [ReferenceCandidate] {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
      .drop(while: { $0 == "@" || $0 == "[" }).lowercased()
    let candidates = records.map {
      ReferenceCandidate(id: $0.id, title: $0.title, kind: .record)
    } + blocks.map {
      ReferenceCandidate(
        id: $0.id,
        title: $0.text.isEmpty ? $0.type.accessibilityName : $0.text,
        kind: .block)
    }
    return candidates
      .filter { normalized.isEmpty || $0.title.localizedCaseInsensitiveContains(normalized) }
      .sorted {
        let order = $0.title.localizedCaseInsensitiveCompare($1.title)
        return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
      }
  }

  public static func recordReferences(in text: String) -> [RecordReference] {
    references(in: text)
  }

  public static func references(in text: String, targetID: UUID? = nil) -> [RecordReference] {
    let source = text as NSString
    var result: [RecordReference] = []
    var cursor = 0
    while cursor < source.length {
      let searchRange = NSRange(location: cursor, length: source.length - cursor)
      let wikiOpen = source.range(of: "[[", options: [], range: searchRange)
      let mentionOpen = source.range(of: "@[", options: [], range: searchRange)
      let useMention = mentionOpen.location != NSNotFound
        && (wikiOpen.location == NSNotFound || mentionOpen.location < wikiOpen.location)
      let open = useMention ? mentionOpen : wikiOpen
      guard open.location != NSNotFound else { break }
      let valueStart = NSMaxRange(open)
      let close = source.range(
        of: useMention ? "]" : "]]",
        options: [],
        range: NSRange(location: valueStart, length: source.length - valueStart))
      guard close.location != NSNotFound else { break }
      let value = source.substring(with: NSRange(location: valueStart, length: close.location - valueStart))
      let rawID = value.split(separator: "|", maxSplits: 1).first.map(String.init) ?? value
      if let parsedID = UUID(uuidString: rawID), targetID == nil || targetID == parsedID {
        result.append(RecordReference(
          targetID: parsedID,
          range: NSRange(location: open.location, length: NSMaxRange(close) - open.location),
          syntax: useMention ? .mention : .wikiLink))
      }
      cursor = max(NSMaxRange(close), valueStart)
    }
    return result
  }

  public static func resolve(
    _ reference: RecordReference,
    in candidates: [ReferenceCandidate]
  ) -> ReferenceCandidate? {
    candidates.first { $0.id == reference.targetID }
  }

  public static func targetID(atUTF16Offset offset: Int, in text: String) -> UUID? {
    references(in: text).first { NSLocationInRange(offset, $0.range) }?.targetID
  }

  public static func backlinks(to targetID: UUID, in documents: [BlockDocument]) -> [UUID] {
    documents.flatMap { document in
      document.blocks.filter {
        !references(in: $0.text, targetID: targetID).isEmpty
      }.map(\.id)
    }
  }
}

public enum HTMLPasteSanitizer {
  public static func plainText(_ html: String) -> String {
    var value = html
    value = value.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
    value = value.replacingOccurrences(of: "</p>\\s*<p[^>]*>", with: "\n", options: .regularExpression)
    value = value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    return value
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
  }
}

#if canImport(AppKit)
import AppKit

@MainActor
public final class SynoraTextView: NSView, NSTextViewDelegate {
  private let textView: NSTextView
  public var onTextChange: (@MainActor (String) -> Void)?

  public init() {
    textView = NSTextView(usingTextLayoutManager: true)
    super.init(frame: .zero)
    configure()
  }

  required init?(coder: NSCoder) {
    textView = NSTextView(usingTextLayoutManager: true)
    super.init(coder: coder)
    configure()
  }

  public var string: String {
    get { textView.string }
    set { textView.string = newValue }
  }

  public var usesTextLayoutManager: Bool { textView.textLayoutManager != nil }

  public func setDocumentText(_ text: String) {
    let selection = textView.selectedRange()
    textView.textStorage?.setAttributedString(NSAttributedString(string: text))
    textView.setSelectedRange(
      NSRange(location: min(selection.location, (string as NSString).length), length: 0))
  }

  public func textDidChange(_ notification: Notification) {
    onTextChange?(string)
  }

  private func configure() {
    textView.delegate = self
    textView.isRichText = false
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.isEditable = true
    textView.isSelectable = true
    textView.textContainerInset = NSSize(width: 18, height: 16)
    textView.font = .systemFont(ofSize: 16)
    addSubview(textView)
  }

  public override func layout() {
    super.layout()
    textView.frame = bounds
  }
}
#endif
