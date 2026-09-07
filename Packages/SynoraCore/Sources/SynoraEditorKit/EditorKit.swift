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
          type: first.type, attributes: first.attributes, unknownFields: first.unknownFields))
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
        unknownFields: blocks[endIndex].unknownFields
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
    func visit(_ parentID: UUID?) -> [Block] {
      document.children(of: parentID).flatMap { block in
        [block] + visit(block.id)
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

public enum EditorCommand: Hashable, Sendable {
  case insertText(String)
  case setBlockType(BlockType)
  case toggleTask
  case deleteBlock
  case splitBlock(atUTF16Offset: Int, newID: UUID)
  case mergeWithNext
  case indent
  case outdent
}

public enum EditorError: Error, Equatable, Sendable {
  case invalidSelection
  case unsupportedCommand
  case noUndo
  case noRedo
}

public struct EditorSession: Sendable {
  public private(set) var document: BlockDocument
  private var undoStack: [BlockDocument] = []
  private var redoStack: [BlockDocument] = []

  public init(document: BlockDocument) { self.document = document }

  @discardableResult
  public mutating func apply(range: NSRange, replacement: String, marked: Bool = false) throws
    -> BlockDocument
  {
    guard !marked else { return document }
    let next = try TextStorageAdapter(document: document).applying(
      range: range, replacement: replacement)
    guard next != document else { return document }
    undoStack.append(document)
    redoStack.removeAll()
    document = next
    return next
  }

  @discardableResult
  public mutating func execute(_ command: EditorCommand, blockID: UUID) throws -> BlockDocument {
    let next: BlockDocument
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
    }
    guard next != document else { return document }
    undoStack.append(document)
    redoStack.removeAll()
    document = next
    return next
  }

  public mutating func undo() throws -> BlockDocument {
    guard let previous = undoStack.popLast() else { throw EditorError.noUndo }
    redoStack.append(document)
    document = previous
    return document
  }

  public mutating func redo() throws -> BlockDocument {
    guard let next = redoStack.popLast() else { throw EditorError.noRedo }
    undoStack.append(document)
    document = next
    return document
  }
}

public enum MarkdownShortcut {
  public static func block(for line: String) -> (type: BlockType, text: String)? {
    let shortcuts: [(String, BlockType)] = [
      ("### ", .heading3), ("## ", .heading2), ("# ", .heading1),
      ("- [ ] ", .task), ("- ", .bulletedList), ("> ", .quote), ("---", .divider),
    ]
    guard let match = shortcuts.first(where: { line.hasPrefix($0.0) }) else { return nil }
    return (match.1, String(line.dropFirst(match.0.count)))
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
