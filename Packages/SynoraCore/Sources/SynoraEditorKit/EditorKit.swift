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
    for (index, block) in document.children().enumerated() {
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
    var blocks = document.children()
    guard let targetIndex = ranges.firstIndex(where: {
      NSLocationInRange(range.location, $0.range) || range.location == NSMaxRange($0.range)
    }) else { throw EditorError.invalidSelection }
    let target = ranges[targetIndex]
    let localStart = range.location - target.range.location
    let localEnd = min(NSMaxRange(range), NSMaxRange(target.range)) - target.range.location
    let original = blocks[targetIndex].text as NSString
    let localRange = NSRange(location: max(0, localStart), length: max(0, localEnd - localStart))
    blocks[targetIndex].text = original.replacingCharacters(in: localRange, with: replacement)
    return try BlockDocument(recordID: document.recordID, blocks: blocks)
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
}

public enum EditorError: Error, Equatable, Sendable {
  case invalidSelection
  case unsupportedCommand
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
