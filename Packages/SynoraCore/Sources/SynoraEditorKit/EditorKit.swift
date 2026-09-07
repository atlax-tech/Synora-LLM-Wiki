import Foundation
import SynoraDomain

#if canImport(AppKit)
import AppKit
#if canImport(os)
import os
#endif
#endif

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

  public func range(for blockID: UUID) -> NSRange? {
    ranges.first(where: { $0.blockID == blockID })?.range
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
    if pieces.count == 1, startIndex == endIndex {
      first.inlineAttributes = Self.attributesAfterReplacement(
        first.inlineAttributes,
        replacing: NSRange(location: startOffset, length: endOffset - startOffset),
        replacementLength: (pieces.first ?? "").utf16.count)
    } else if pieces.count == 1 {
      let endSource = blocks[endIndex]
      first.inlineAttributes = Self.attributesBefore(
        first.inlineAttributes, offset: startOffset)
        + Self.attributesAfter(
          endSource.inlineAttributes,
          offset: endOffset,
          textLength: (endSource.text as NSString).length,
          shiftedBy: (prefix + (pieces.first ?? "")).utf16.count)
    } else {
      first.inlineAttributes = Self.attributesBefore(
        first.inlineAttributes, offset: startOffset)
    }
    updated.append(first)
    if pieces.count > 1 {
      for piece in pieces.dropFirst().dropLast() {
        updated.append(Block(
          id: UUID(), recordID: document.recordID, position: updated.count, text: piece,
          type: first.type, inlineAttributes: [], attributes: first.attributes,
          unknownFields: first.unknownFields,
          content: first.content))
      }
      let lastID = endIndex == startIndex ? UUID() : blocks[endIndex].id
      let lastSource = blocks[endIndex]
      let lastLength = (lastSource.text as NSString).length
      let last = Block(
        id: lastID,
        recordID: blocks[endIndex].recordID,
        position: updated.count,
        text: (pieces.last ?? "") + suffix,
        revision: blocks[endIndex].revision,
        parentID: blocks[endIndex].parentID,
        type: blocks[endIndex].type,
        orderKey: blocks[endIndex].orderKey,
        inlineAttributes: Self.attributesAfter(
          lastSource.inlineAttributes,
          offset: endOffset,
          textLength: lastLength,
          shiftedBy: (pieces.last ?? "").utf16.count),
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

  private static func attributesBefore(
    _ attributes: [InlineAttribute],
    offset: Int
  ) -> [InlineAttribute] {
    attributes.compactMap { attribute in
      let end = min(NSMaxRange(attribute.range), offset)
      guard end > attribute.range.location else { return nil }
      return InlineAttribute(
        range: NSRange(location: attribute.range.location, length: end - attribute.range.location),
        style: attribute.style,
        value: attribute.value)
    }
  }

  private static func attributesAfter(
    _ attributes: [InlineAttribute],
    offset: Int,
    textLength: Int,
    shiftedBy shift: Int = 0
  ) -> [InlineAttribute] {
    attributes.compactMap { attribute in
      let start = max(attribute.range.location, offset)
      guard start < min(NSMaxRange(attribute.range), textLength) else { return nil }
      return InlineAttribute(
          range: NSRange(
          location: start - offset + shift,
          length: min(NSMaxRange(attribute.range), textLength) - start),
        style: attribute.style,
        value: attribute.value)
    }
  }

  private static func attributesAfterReplacement(
    _ attributes: [InlineAttribute],
    replacing range: NSRange,
    replacementLength: Int
  ) -> [InlineAttribute] {
    let delta = replacementLength - range.length
    return attributes.flatMap { attribute -> [InlineAttribute] in
      let start = attribute.range.location
      let end = NSMaxRange(attribute.range)
      if range.length == 0, start < range.location, end > range.location {
        return [InlineAttribute(
          range: NSRange(location: start, length: attribute.range.length + replacementLength),
          style: attribute.style,
          value: attribute.value)]
      }
      if end <= range.location { return [attribute] }
      if start >= NSMaxRange(range) {
        return [InlineAttribute(
          range: NSRange(location: start + delta, length: attribute.range.length),
          style: attribute.style,
          value: attribute.value)]
      }
      var pieces: [InlineAttribute] = []
      if start < range.location {
        pieces.append(InlineAttribute(
          range: NSRange(location: start, length: range.location - start),
          style: attribute.style,
          value: attribute.value))
      }
      if end > NSMaxRange(range) {
        pieces.append(InlineAttribute(
          range: NSRange(
            location: range.location + replacementLength,
            length: end - NSMaxRange(range)),
          style: attribute.style,
          value: attribute.value))
      }
      return pieces
    }
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
  case setAssetPlacements([AssetPlacement])
  case reorderAsset(UUID, before: UUID?)
  case replaceAsset(UUID, with: AssetPlacement)
  case setAssetCaption(UUID, String)
  case setAssetCrop(UUID, [String: Double])
  case setMediaLayout(MediaLayout)
  case setLinkCard(LinkCard)
}

public enum EditorError: Error, Equatable, Sendable {
  case invalidSelection
  case unsupportedCommand
  case noUndo
  case noRedo
  case invalidURL
  case invalidPaste
  case emptyQuery
}

public enum InlineFormatting {
  public static func isCovered(
    _ attributes: [InlineAttribute],
    style: InlineStyle,
    range: NSRange
  ) -> Bool {
    guard range.length > 0 else { return false }
    var cursor = range.location
    for attribute in attributes
      .filter({ $0.style == style && NSMaxRange($0.range) > range.location && $0.range.location < NSMaxRange(range) })
      .sorted(by: { $0.range.location < $1.range.location }) {
      if attribute.range.location > cursor { return false }
      cursor = max(cursor, NSMaxRange(attribute.range))
      if cursor >= NSMaxRange(range) { return true }
    }
    return false
  }

  public static func styles(
    _ attributes: [InlineAttribute],
    covering range: NSRange
  ) -> Set<InlineStyle> {
    Set(InlineStyle.allCases.filter { isCovered(attributes, style: $0, range: range) })
  }

  public static func applying(
    _ attributes: [InlineAttribute],
    style: InlineStyle,
    range: NSRange,
    enabled: Bool,
    value: String? = nil
  ) -> [InlineAttribute] {
    var result = attributes.flatMap { attribute -> [InlineAttribute] in
      guard attribute.style == style else { return [attribute] }
      let start = attribute.range.location
      let end = NSMaxRange(attribute.range)
      if end <= range.location || start >= NSMaxRange(range) { return [attribute] }
      var pieces: [InlineAttribute] = []
      if start < range.location {
        pieces.append(InlineAttribute(
          range: NSRange(location: start, length: range.location - start),
          style: style,
          value: attribute.value))
      }
      if end > NSMaxRange(range) {
        pieces.append(InlineAttribute(
          range: NSRange(location: NSMaxRange(range), length: end - NSMaxRange(range)),
          style: style,
          value: attribute.value))
      }
      return pieces
    }
    if enabled { result.append(InlineAttribute(range: range, style: style, value: value)) }
    return normalized(result)
  }

  public static func normalized(_ attributes: [InlineAttribute]) -> [InlineAttribute] {
    var result: [InlineAttribute] = []
    for attribute in attributes.filter({ $0.range.length > 0 }).sorted(by: {
      ($0.range.location, NSMaxRange($0.range), $0.style.rawValue, $0.value ?? "")
        < ($1.range.location, NSMaxRange($1.range), $1.style.rawValue, $1.value ?? "")
    }) {
      guard let previous = result.last,
        previous.style == attribute.style,
        previous.value == attribute.value,
        NSMaxRange(previous.range) >= attribute.range.location
      else {
        result.append(attribute)
        continue
      }
      result[result.count - 1] = InlineAttribute(
        range: NSRange(
          location: previous.range.location,
          length: max(NSMaxRange(previous.range), NSMaxRange(attribute.range))
            - previous.range.location),
        style: previous.style,
        value: previous.value)
    }
    return result
  }
}

public struct EditorFormatBarState: Hashable, Sendable {
  public let selection: NSRange
  public let isPresented: Bool
  public let activeStyles: Set<InlineStyle>

  public init(document: BlockDocument, selection: NSRange) {
    self.selection = selection
    let adapter = TextStorageAdapter(document: document)
    guard selection.location >= 0, selection.length > 0,
      NSMaxRange(selection) <= (adapter.text as NSString).length else {
      isPresented = false
      activeStyles = []
      return
    }
    let selected = adapter.ranges.compactMap { mapped -> Set<InlineStyle>? in
      let start = max(selection.location, mapped.range.location)
      let end = min(NSMaxRange(selection), NSMaxRange(mapped.range))
      guard end > start, let block = document.block(id: mapped.blockID) else { return nil }
      return InlineFormatting.styles(
        block.inlineAttributes,
        covering: NSRange(location: start - mapped.range.location, length: end - start))
    }
    isPresented = !selected.isEmpty
    activeStyles = selected.dropFirst().reduce(selected.first ?? []) {
      $0.intersection($1)
    }
  }
}

public struct FindOptions: OptionSet, Codable, Hashable, Sendable {
  public let rawValue: Int

  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let caseSensitive = Self(rawValue: 1 << 0)
  public static let wholeWord = Self(rawValue: 1 << 1)
}

public struct SearchMatch: Hashable, Sendable {
  public let blockID: UUID?
  public let range: NSRange
  public let value: String

  public init(blockID: UUID? = nil, range: NSRange, value: String) {
    self.blockID = blockID
    self.range = range
    self.value = value
  }
}

public enum TextSearch {
  public static func ranges(
    in text: String,
    query: String,
    options: FindOptions = []
  ) -> [NSRange] {
    guard !query.isEmpty else { return [] }
    let source = text as NSString
    let needle = query as NSString
    var result: [NSRange] = []
    var cursor = 0
    var searchOptions: NSString.CompareOptions = []
    if !options.contains(.caseSensitive) { searchOptions.insert(.caseInsensitive) }
    while cursor <= source.length - needle.length {
      let range = source.range(
        of: needle as String,
        options: searchOptions,
        range: NSRange(location: cursor, length: source.length - cursor))
      guard range.location != NSNotFound else { break }
      if !options.contains(.wholeWord) || isWordBoundary(range, in: source) {
        result.append(range)
      }
      cursor = max(NSMaxRange(range), cursor + 1)
    }
    return result
  }

  public static func matches(
    in document: BlockDocument,
    query: String,
    options: FindOptions = []
  ) -> [SearchMatch] {
    guard !query.isEmpty else { return [] }
    let adapter = TextStorageAdapter(document: document)
    let source = adapter.text as NSString
    return ranges(in: adapter.text, query: query, options: options).map { range in
      let blockID = adapter.ranges.first(where: {
        NSLocationInRange(range.location, $0.range)
          || NSLocationInRange(max(range.location, NSMaxRange(range) - 1), $0.range)
      })?.blockID
      return SearchMatch(blockID: blockID, range: range, value: source.substring(with: range))
    }
  }

  public static func find(
    in document: BlockDocument,
    query: String,
    options: FindOptions = []
  ) -> [SearchMatch] {
    matches(in: document, query: query, options: options)
  }

  public static func replacingAll(
    in document: BlockDocument,
    query: String,
    with replacement: String,
    options: FindOptions = []
  ) throws -> BlockDocument {
    guard !query.isEmpty else { throw EditorError.emptyQuery }
    var next = document
    for match in matches(in: document, query: query, options: options).reversed() {
      next = try TextStorageAdapter(document: next).applying(
        range: match.range,
        replacement: replacement)
    }
    return next
  }

  private static func isWordBoundary(_ range: NSRange, in source: NSString) -> Bool {
    func isWord(_ value: unichar) -> Bool {
      CharacterSet.alphanumerics.contains(UnicodeScalar(value)!) || value == 95
    }
    let before = range.location > 0 ? source.character(at: range.location - 1) : nil
    let after = NSMaxRange(range) < source.length ? source.character(at: NSMaxRange(range)) : nil
    return (before == nil || !isWord(before!)) && (after == nil || !isWord(after!))
  }
}

public struct SpellingIssue: Hashable, Sendable {
  public let range: NSRange
  public let word: String

  public init(range: NSRange, word: String) {
    self.range = range
    self.word = word
  }
}

public enum SpellChecker {
  #if canImport(AppKit)
  @MainActor
  public static func issues(in text: String, language: String? = nil) -> [SpellingIssue] {
    let checker = NSSpellChecker.shared
    let source = text as NSString
    var result: [SpellingIssue] = []
    var cursor = 0
    while cursor < source.length {
      let issue = checker.checkSpelling(of: text, startingAt: cursor)
      guard issue.location != NSNotFound, issue.length > 0 else { break }
      result.append(SpellingIssue(
        range: issue,
        word: source.substring(with: issue)))
      cursor = NSMaxRange(issue)
    }
    _ = language
    return result
  }
  #else
  public static func issues(in text: String, language: String? = nil) -> [SpellingIssue] {
    _ = language
    return []
  }
  #endif
}

public struct RichTextFragment: Codable, Hashable, Sendable {
  public let text: String
  public let inlineAttributes: [InlineAttribute]

  public init(text: String, inlineAttributes: [InlineAttribute] = []) {
    self.text = text
    self.inlineAttributes = inlineAttributes
  }

  public var inlineMarks: [InlineAttribute] { inlineAttributes }
}

public enum PastePayload: Hashable, Sendable {
  case structured(BlockClipboard)
  case richText(RichTextFragment)
  case html(String)
  case plainText(String)
  case files([URL])
}

public struct PreparedPaste: Hashable, Sendable {
  public let text: String?
  public let inlineAttributes: [InlineAttribute]
  public let clipboard: BlockClipboard?
  public let fileURLs: [URL]

  public init(
    text: String? = nil,
    inlineAttributes: [InlineAttribute] = [],
    clipboard: BlockClipboard? = nil,
    fileURLs: [URL] = []
  ) {
    self.text = text
    self.inlineAttributes = inlineAttributes
    self.clipboard = clipboard
    self.fileURLs = fileURLs
  }
}

public enum EditorURLValidator {
  public static func isSupported(_ value: String) -> Bool {
    LinkCard(url: value).isSupportedURL
  }
}

public enum PasteboardDecoder {
  public static func prepare(_ payload: PastePayload) throws -> PreparedPaste {
    switch payload {
    case .structured(let clipboard):
      try validate(clipboard)
      return PreparedPaste(clipboard: clipboard)
    case .richText(let fragment):
      guard validate(fragment.inlineAttributes, text: fragment.text) else {
        throw EditorError.invalidPaste
      }
      return PreparedPaste(
        text: fragment.text,
        inlineAttributes: InlineFormatting.normalized(fragment.inlineAttributes))
    case .html(let html):
      return PreparedPaste(text: HTMLPasteSanitizer.plainText(html))
    case .plainText(let text):
      return PreparedPaste(text: text)
    case .files(let urls):
      guard urls.allSatisfy({ $0.isFileURL }) else { throw EditorError.invalidPaste }
      return PreparedPaste(fileURLs: urls)
    }
  }

  public static func structured(_ data: Data) throws -> BlockClipboard {
    guard let clipboard = try? JSONDecoder().decode(BlockClipboard.self, from: data) else {
      throw EditorError.invalidPaste
    }
    try validate(clipboard)
    return clipboard
  }

  private static func validate(_ clipboard: BlockClipboard) throws {
    guard !clipboard.blocks.isEmpty else { throw EditorError.invalidPaste }
    let IDs = clipboard.blocks.map(\.id)
    guard Set(IDs).count == IDs.count else { throw EditorError.invalidPaste }
    guard Set(clipboard.blocks.map(\.recordID)).count == 1 else {
      throw EditorError.invalidPaste
    }
    let byID = Dictionary(uniqueKeysWithValues: clipboard.blocks.map { ($0.id, $0) })
    for block in clipboard.blocks {
      let length = (block.text as NSString).length
      guard block.inlineAttributes.allSatisfy({
        $0.range.location >= 0 && $0.range.length > 0
          && $0.range.location <= length && $0.range.length <= length - $0.range.location
      }) else { throw EditorError.invalidPaste }
      switch block.content {
      case .table? where block.type != .table:
        throw EditorError.invalidPaste
      case .assets? where ![.image, .gallery, .video, .audio, .pdf, .file].contains(block.type):
        throw EditorError.invalidPaste
      case .link(let card)? where block.type != .link || !EditorURLValidator.isSupported(card.url):
        throw EditorError.invalidPaste
      default:
        break
      }
      if let parentID = block.parentID, let parent = byID[parentID], !parent.type.acceptsChildren {
        throw EditorError.invalidPaste
      }
      var visited: Set<UUID> = []
      var ancestor = block.parentID
      while let parentID = ancestor, let parent = byID[parentID] {
        guard visited.insert(parentID).inserted else { throw EditorError.invalidPaste }
        ancestor = parent.parentID
      }
    }
  }

  private static func validate(_ attributes: [InlineAttribute], text: String) -> Bool {
    let length = (text as NSString).length
    return attributes.allSatisfy {
      $0.range.location >= 0 && $0.range.length > 0
        && $0.range.location <= length && $0.range.length <= length - $0.range.location
        && ($0.style != .link || ($0.value.map(EditorURLValidator.isSupported) ?? false))
    }
  }
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

  /// Adopts a document produced by an asynchronous media operation while
  /// keeping the existing editor undo history.
  @discardableResult
  public mutating func adopt(_ next: BlockDocument) -> BlockDocument {
    commit(next)
  }

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
    case .setAssetPlacements(let placements):
      next = try document.settingAssetPlacements(placements, for: blockID)
    case .reorderAsset(let assetID, let targetAssetID):
      next = try document.reorderingAsset(assetID, in: blockID, before: targetAssetID)
    case .replaceAsset(let assetID, let replacement):
      next = try document.replacingAsset(assetID, with: replacement, in: blockID)
    case .setAssetCaption(let assetID, let caption):
      next = try document.settingAssetCaption(caption, for: assetID, in: blockID)
    case .setAssetCrop(let assetID, let crop):
      next = try document.settingAssetCrop(crop, for: assetID, in: blockID)
    case .setMediaLayout(let layout):
      next = try document.settingMediaLayout(layout, for: blockID)
    case .setLinkCard(let card):
      next = try document.settingLinkCard(card, for: blockID)
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

  public func preparePaste(_ payload: PastePayload) throws -> PreparedPaste {
    try PasteboardDecoder.prepare(payload)
  }

  @discardableResult
  public mutating func paste(
    _ payload: PastePayload,
    at range: NSRange? = nil,
    into parentID: UUID? = nil,
    before siblingID: UUID? = nil,
    idGenerator: any IDGenerator = UUIDGenerator()
  ) throws -> BlockDocument {
    let prepared = try PasteboardDecoder.prepare(payload)
    if let clipboard = prepared.clipboard {
      return commit(try document.pasting(
        clipboard,
        into: parentID,
        before: siblingID,
        idGenerator: idGenerator))
    }
    guard prepared.fileURLs.isEmpty, let text = prepared.text else {
      throw EditorError.unsupportedCommand
    }
    let adapter = TextStorageAdapter(document: document)
    let insertionRange = try rangeForPaste(range, in: adapter)
    var next = try adapter.applying(range: insertionRange, replacement: text)
    if !prepared.inlineAttributes.isEmpty {
      next = try applyingPastedAttributes(
        prepared.inlineAttributes,
        textLength: (text as NSString).length,
        atGlobalOffset: insertionRange.location,
        to: next)
    }
    return commit(next, focus: focus(atGlobalOffset: insertionRange.location + (text as NSString).length, in: next))
  }

  public func formattingState(for selection: NSRange) -> EditorFormatBarState {
    EditorFormatBarState(document: document, selection: selection)
  }

  @discardableResult
  public mutating func applyFormatting(
    _ style: InlineStyle,
    in selection: NSRange,
    linkURL: String? = nil
  ) throws -> BlockDocument {
    let adapter = TextStorageAdapter(document: document)
    let source = adapter.text as NSString
    guard selection.location >= 0, selection.length > 0,
      NSMaxRange(selection) <= source.length,
      Self.isComposedBoundary(selection.location, in: source),
      Self.isComposedBoundary(NSMaxRange(selection), in: source)
    else { throw EditorError.invalidSelection }
    if let linkURL {
      guard style == .link, EditorURLValidator.isSupported(linkURL) else {
        throw EditorError.invalidURL
      }
    }
    let segments = adapter.ranges.compactMap { mapped -> (UUID, NSRange)? in
      let start = max(selection.location, mapped.range.location)
      let end = min(NSMaxRange(selection), NSMaxRange(mapped.range))
      guard end > start else { return nil }
      return (mapped.blockID, NSRange(location: start - mapped.range.location, length: end - start))
    }
    guard !segments.isEmpty else { throw EditorError.invalidSelection }
    let enabled = !segments.allSatisfy { blockID, range in
      guard let block = document.block(id: blockID) else { return false }
      return InlineFormatting.isCovered(block.inlineAttributes, style: style, range: range)
    }
    if style == .link, enabled, linkURL == nil {
      throw EditorError.invalidURL
    }
    var next = document
    for (blockID, range) in segments {
      guard let block = next.block(id: blockID) else { throw EditorError.invalidSelection }
      let attributes = InlineFormatting.applying(
        block.inlineAttributes,
        style: style,
        range: range,
        enabled: enabled,
        value: style == .link ? linkURL : nil)
      next = try next.settingInlineAttributes(attributes, for: blockID)
    }
    return commit(next)
  }

  @discardableResult
  public mutating func applyFormat(
    _ style: InlineStyle,
    in selection: NSRange,
    linkURL: String? = nil
  ) throws -> BlockDocument {
    try applyFormatting(style, in: selection, linkURL: linkURL)
  }

  public func find(query: String, options: FindOptions = []) -> [SearchMatch] {
    TextSearch.matches(in: document, query: query, options: options)
  }

  @discardableResult
  public mutating func replaceAll(
    query: String,
    with replacement: String,
    options: FindOptions = []
  ) throws -> BlockDocument {
    guard !query.isEmpty else { throw EditorError.emptyQuery }
    return commit(try TextSearch.replacingAll(
      in: document,
      query: query,
      with: replacement,
      options: options))
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
  public mutating func placeAsset(
    _ placement: AssetPlacement,
    in blockID: UUID
  ) throws -> BlockDocument {
    try execute(
      .setAssetPlacements(document.placingAsset(placement, in: blockID).assetPlacements(in: blockID)),
      blockID: blockID)
  }

  @discardableResult
  public mutating func removeAsset(
    _ assetID: UUID,
    from blockID: UUID
  ) throws -> BlockDocument {
    let placements = try document.removingAsset(assetID, from: blockID).assetPlacements(in: blockID)
    return try execute(.setAssetPlacements(placements), blockID: blockID)
  }

  @discardableResult
  public mutating func reorderAsset(
    _ assetID: UUID,
    in blockID: UUID,
    before targetAssetID: UUID? = nil
  ) throws -> BlockDocument {
    try execute(.reorderAsset(assetID, before: targetAssetID), blockID: blockID)
  }

  @discardableResult
  public mutating func replaceAsset(
    _ assetID: UUID,
    with replacement: AssetPlacement,
    in blockID: UUID
  ) throws -> BlockDocument {
    try execute(.replaceAsset(assetID, with: replacement), blockID: blockID)
  }

  @discardableResult
  public mutating func setAssetCaption(
    _ caption: String,
    for assetID: UUID,
    in blockID: UUID
  ) throws -> BlockDocument {
    try execute(.setAssetCaption(assetID, caption), blockID: blockID)
  }

  @discardableResult
  public mutating func setAssetCrop(
    _ crop: [String: Double],
    for assetID: UUID,
    in blockID: UUID
  ) throws -> BlockDocument {
    try execute(.setAssetCrop(assetID, crop), blockID: blockID)
  }

  @discardableResult
  public mutating func setMediaLayout(
    _ layout: MediaLayout,
    in blockID: UUID
  ) throws -> BlockDocument {
    try execute(.setMediaLayout(layout), blockID: blockID)
  }

  @discardableResult
  public mutating func setLinkCard(
    _ card: LinkCard,
    in blockID: UUID
  ) throws -> BlockDocument {
    try execute(.setLinkCard(card), blockID: blockID)
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

  private func rangeForPaste(
    _ requested: NSRange?,
    in adapter: TextStorageAdapter
  ) throws -> NSRange {
    if let requested {
      let length = (adapter.text as NSString).length
      guard requested.location >= 0, requested.length >= 0,
        NSMaxRange(requested) <= length,
        Self.isComposedBoundary(requested.location, in: adapter.text as NSString),
        Self.isComposedBoundary(NSMaxRange(requested), in: adapter.text as NSString)
      else { throw EditorError.invalidSelection }
      return requested
    }
    if let focus, focus.tableCell == nil,
      let mapped = adapter.ranges.first(where: { $0.blockID == focus.blockID }) {
      return NSRange(location: mapped.range.location + focus.utf16Offset, length: 0)
    }
    return NSRange(location: (adapter.text as NSString).length, length: 0)
  }

  private func applyingPastedAttributes(
    _ attributes: [InlineAttribute],
    textLength: Int,
    atGlobalOffset offset: Int,
    to document: BlockDocument
  ) throws -> BlockDocument {
    let adapter = TextStorageAdapter(document: document)
    var next = document
    for mapped in adapter.ranges {
      let blockStart = max(mapped.range.location, offset)
      let blockEnd = min(NSMaxRange(mapped.range), offset + textLength)
      guard blockEnd > blockStart, let block = next.block(id: mapped.blockID) else { continue }
      var blockAttributes = block.inlineAttributes
      for attribute in attributes {
        let markStart = offset + attribute.range.location
        let markEnd = offset + NSMaxRange(attribute.range)
        let start = max(blockStart, markStart)
        let end = min(blockEnd, markEnd)
        guard end > start else { continue }
        blockAttributes.append(InlineAttribute(
          range: NSRange(location: start - mapped.range.location, length: end - start),
          style: attribute.style,
          value: attribute.value))
      }
      next = try next.settingInlineAttributes(
        InlineFormatting.normalized(blockAttributes),
        for: mapped.blockID)
    }
    return next
  }

  private func focus(atGlobalOffset offset: Int, in document: BlockDocument) -> EditorFocus? {
    let adapter = TextStorageAdapter(document: document)
    guard let mapped = adapter.ranges.first(where: {
      offset <= NSMaxRange($0.range)
    }), let block = document.block(id: mapped.blockID) else { return nil }
    return EditorFocus(
      blockID: mapped.blockID,
      utf16Offset: min(max(offset - mapped.range.location, 0), (block.text as NSString).length))
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
    value = value.replacingOccurrences(
      of: "<(script|style|iframe|object|embed)[^>]*>[\\s\\S]*?</\\1>",
      with: "",
      options: [.regularExpression, .caseInsensitive])
    value = value.replacingOccurrences(of: "<!--.*?-->", with: "", options: [.regularExpression, .caseInsensitive])
    value = value.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
    value = value.replacingOccurrences(
      of: "</(p|div|li|h[1-6])>\\s*<(p|div|li|h[1-6])[^>]*>",
      with: "\n",
      options: [.regularExpression, .caseInsensitive])
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
private final class SynoraTextInputView: NSTextView {
  var onMarkedTextChanged: ((Bool) -> Void)?
  var onPaint: (() -> Void)?
  private(set) var composing = false

  override func setMarkedText(
    _ string: Any,
    selectedRange: NSRange,
    replacementRange: NSRange
  ) {
    composing = true
    onMarkedTextChanged?(true)
    super.setMarkedText(
      string, selectedRange: selectedRange, replacementRange: replacementRange)
  }

  override func unmarkText() {
    super.unmarkText()
    composing = false
    onMarkedTextChanged?(false)
  }

  override func insertText(_ string: Any, replacementRange: NSRange) {
    let wasComposing = composing || hasMarkedText()
    super.insertText(string, replacementRange: replacementRange)
    if wasComposing {
      composing = false
      onMarkedTextChanged?(false)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    onPaint?()
  }
}

@MainActor
public final class SynoraTextView: NSView, NSTextViewDelegate {
  private let textView: SynoraTextInputView
  public var onTextChange: (@MainActor (String) -> Void)?
  public var onSelectionChange: (@MainActor (NSRange) -> Void)?
  private var pendingMarkedTextChange = false
  private var lastEmittedString = ""

  #if canImport(os)
  private var pendingPaintSignpost: OSSignpostID?
  #else
  private var pendingPaintSignpost: UInt64?
  #endif

  public init() {
    textView = SynoraTextInputView(usingTextLayoutManager: true)
    super.init(frame: .zero)
    configure()
  }

  required init?(coder: NSCoder) {
    textView = SynoraTextInputView(usingTextLayoutManager: true)
    super.init(coder: coder)
    configure()
  }

  public var string: String {
    get { textView.string }
    set {
      textView.string = newValue
      lastEmittedString = newValue
    }
  }

  public var usesTextLayoutManager: Bool { textView.textLayoutManager != nil }

  public var selectedRange: NSRange { textView.selectedRange() }

  public func setSelectedRange(_ range: NSRange) {
    textView.setSelectedRange(range)
  }

  public func setDocumentText(_ text: String) {
    let selection = textView.selectedRange()
    textView.textStorage?.setAttributedString(NSAttributedString(string: text))
    lastEmittedString = text
    textView.setSelectedRange(
      NSRange(location: min(selection.location, (string as NSString).length), length: 0))
  }

  public func textDidChange(_ notification: Notification) {
    // Marked text is an in-progress IME composition. Persist only after the
    // input method commits it, otherwise pinyin/phonetic intermediates become
    // durable document content.
    guard !textView.composing, !textView.hasMarkedText() else {
      pendingMarkedTextChange = true
      return
    }
    pendingMarkedTextChange = false
    emitTextChange()
  }

  public func textViewDidChangeSelection(_ notification: Notification) {
    onSelectionChange?(textView.selectedRange())
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
    textView.onMarkedTextChanged = { [weak self] marked in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.pendingMarkedTextChange = true
        if !marked { self.flushMarkedTextChange() }
      }
    }
    textView.onPaint = { [weak self] in self?.endPaintSignpost() }
    textView.setAccessibilityRole(.textArea)
    textView.setAccessibilityLabel("Record body")
    textView.setAccessibilityIdentifier("editor-body")
    textView.setAccessibilityHelp("Edit the selected record")
    addSubview(textView)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier("editor-body-container")
  }

  public override var acceptsFirstResponder: Bool { true }

  public override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(textView)
    super.mouseDown(with: event)
  }

  private func emitTextChange() {
    let value = string
    guard value != lastEmittedString else {
      pendingMarkedTextChange = false
      return
    }
    lastEmittedString = value
    beginPaintSignpost()
    onTextChange?(value)
  }

  private func flushMarkedTextChange() {
    guard pendingMarkedTextChange else { return }
    guard !textView.composing, !textView.hasMarkedText() else {
      DispatchQueue.main.async { [weak self] in self?.flushMarkedTextChange() }
      return
    }
    pendingMarkedTextChange = false
    emitTextChange()
  }

  private func beginPaintSignpost() {
    guard pendingPaintSignpost == nil else { return }
    pendingPaintSignpost = EditorTelemetry.begin("keystrokeToPaint")
  }

  private func endPaintSignpost() {
    guard let pendingPaintSignpost else { return }
    EditorTelemetry.end("keystrokeToPaint", pendingPaintSignpost)
    self.pendingPaintSignpost = nil
  }

  public override func layout() {
    super.layout()
    textView.frame = bounds
  }
}
#endif
