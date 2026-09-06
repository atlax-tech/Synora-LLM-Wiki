import AppKit
import CryptoKit
import Foundation
import OSLog
import SwiftUI

struct TextKit2ProbeResult: Sendable {
  let text: String
  let blockRanges: [NSRange]
  let blockIDs: [UUID]
  let rangesValid: Bool

  static let fixture: Self = {
    let adapter = UTF16BlockAdapter(text: "中文输入🙂\nEnglish e\u{301}\n👩‍💻 attachment")
    return Self(
      text: adapter.text,
      blockRanges: adapter.ranges,
      blockIDs: adapter.ids,
      rangesValid: adapter.rangesAreValid
    )
  }()
}

private struct UTF16BlockAdapter: Sendable {
  struct Block: Sendable {
    let id: UUID
    let range: NSRange
  }

  private(set) var text: String
  private(set) var blocks: [Block]

  var ranges: [NSRange] { blocks.map(\.range) }
  var ids: [UUID] { blocks.map(\.id) }
  var rangesAreValid: Bool {
    let length = (text as NSString).length
    var previousEnd = 0
    for block in blocks {
      guard block.range.location >= previousEnd,
        block.range.location + block.range.length <= length
      else { return false }
      previousEnd = NSMaxRange(block.range)
    }
    return true
  }

  init(text: String) {
    self.text = text
    blocks = Self.makeBlocks(text: text, ids: [])
  }

  mutating func apply(edit range: NSRange, replacement: String, marked: Bool) -> Bool {
    let source = text as NSString
    guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= source.length,
      Self.isComposedCharacterBoundary(range.location, in: source),
      Self.isComposedCharacterBoundary(NSMaxRange(range), in: source)
    else { return false }
    let oldBlocks = blocks
    text = source.replacingCharacters(in: range, with: replacement)
    guard !marked else { return true }
    let delta = (replacement as NSString).length - range.length
    let newRanges = Self.ranges(in: text)
    var used = Set<UUID>()
    blocks = newRanges.map { newRange in
      let matching = oldBlocks.first { block in
        guard !used.contains(block.id) else { return false }
        if NSMaxRange(block.range) <= range.location { return block.range == newRange }
        if block.range.location >= NSMaxRange(range) {
          return NSRange(
            location: block.range.location + delta, length: block.range.length) == newRange
        }
        return false
      }
      if let matching {
        used.insert(matching.id)
        return Block(id: matching.id, range: newRange)
      }
      if let affected = oldBlocks.first(where: { !used.contains($0.id) }) {
        used.insert(affected.id)
        return Block(id: affected.id, range: newRange)
      }
      return Block(id: UUID(), range: newRange)
    }
    return rangesAreValid
  }

  mutating func replaceText(_ newText: String) {
    text = newText
    blocks = Self.makeBlocks(text: newText, ids: blocks.map(\.id))
  }

  private static func makeBlocks(text: String, ids: [UUID]) -> [Block] {
    ranges(in: text).enumerated().map { index, range in
      Block(id: ids.indices.contains(index) ? ids[index] : UUID(), range: range)
    }
  }

  private static func ranges(in text: String) -> [NSRange] {
    let nsText = text as NSString
    var result: [NSRange] = []
    var location = 0
    while location <= nsText.length {
      let line = nsText.lineRange(for: NSRange(location: location, length: 0))
      let end = min(NSMaxRange(line), nsText.length)
      let length =
        end > location
          && nsText.substring(with: NSRange(location: end - 1, length: 1)) == "\n"
        ? end - location - 1
        : end - location
      result.append(NSRange(location: location, length: max(0, length)))
      if end >= nsText.length { break }
      location = end
    }
    return result
  }

  private static func isComposedCharacterBoundary(_ location: Int, in text: NSString) -> Bool {
    guard location > 0, location < text.length else { return true }
    return text.rangeOfComposedCharacterSequence(at: location).location == location
  }
}

private final class TextKitMetrics: @unchecked Sendable {
  private let lock = NSLock()
  private var samples: [Double] = []

  func record(_ duration: Double) {
    lock.lock()
    samples.append(duration)
    if samples.count > 256 { samples.removeFirst() }
    lock.unlock()
  }

  func write(text: String, ranges: [NSRange]) {
    lock.lock()
    let values = samples.sorted()
    lock.unlock()
    guard !values.isEmpty else { return }
    let payload: [String: Any] = [
      "environment": [
        "os": ProcessInfo.processInfo.operatingSystemVersionString,
        "architecture": "arm64",
      ],
      "textSHA256": SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined(),
      "utf16Length": (text as NSString).length,
      "ranges": ranges.map { ["location": $0.location, "length": $0.length] },
      "samples": values.count,
      "p50Milliseconds": percentile(values, at: 0.50) * 1_000,
      "p95Milliseconds": percentile(values, at: 0.95) * 1_000,
      "p99Milliseconds": percentile(values, at: 0.99) * 1_000,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    else { return }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("synora-textkit-metrics.json")
    try? data.write(to: url, options: .atomic)
  }

  private func percentile(_ values: [Double], at fraction: Double) -> Double {
    values[min(values.count - 1, Int(Double(values.count - 1) * fraction))]
  }
}

final class ProbeTextView: NSTextView {
  private var adapter: UTF16BlockAdapter
  private let metrics: TextKitMetrics
  private let signpostLog = OSLog(subsystem: "tech.atlax.SynoraWiki", category: "TextKit2")

  fileprivate init(text: String, metrics: TextKitMetrics) {
    adapter = UTF16BlockAdapter(text: text)
    self.metrics = metrics
    super.init(usingTextLayoutManager: true)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func draw(_ dirtyRect: NSRect) {
    let signpostID = OSSignpostID(log: signpostLog)
    let started = DispatchTime.now().uptimeNanoseconds
    os_signpost(.begin, log: signpostLog, name: "TextKit2 draw", signpostID: signpostID)
    super.draw(dirtyRect)
    os_signpost(.end, log: signpostLog, name: "TextKit2 draw", signpostID: signpostID)
    metrics.record(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000)
    metrics.write(text: adapter.text, ranges: adapter.ranges)
  }

  override func didChangeText() {
    super.didChangeText()
    if markedRange().location == NSNotFound {
      adapter.replaceText(string)
      setAccessibilityValue(string)
      metrics.write(text: adapter.text, ranges: adapter.ranges)
    }
  }

  fileprivate func insertProbeAttachment() {
    let attachment = NSTextAttachment()
    let image = NSImage(size: NSSize(width: 32, height: 20))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSBezierPath(
      roundedRect: NSRect(x: 0, y: 0, width: 32, height: 20), xRadius: 4, yRadius: 4
    ).fill()
    image.unlockFocus()
    attachment.image = image
    let value = NSMutableAttributedString(attachment: attachment)
    value.addAttribute(
      NSAttributedString.Key("NSAccessibilityLabel"),
      value: "Synora attachment",
      range: NSRange(location: 0, length: 1)
    )
    insertText(value, replacementRange: selectedRange())
    setAccessibilityValue(string)
  }
}

extension Notification.Name {
  static let synoraInsertAttachment = Notification.Name("SynoraInsertAttachment")
}

struct TextKit2ProbeView: NSViewRepresentable {
  let initialText: String

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> ProbeTextView {
    let metrics = TextKitMetrics()
    let textView = ProbeTextView(text: initialText, metrics: metrics)
    textView.string = initialText
    textView.isRichText = true
    textView.isEditable = true
    textView.isSelectable = true
    textView.allowsUndo = true
    textView.usesFindBar = true
    textView.textContainerInset = NSSize(width: 8, height: 8)
    textView.setAccessibilityRole(.textArea)
    textView.setAccessibilityLabel("TextKit 2 probe editor")
    textView.setAccessibilityIdentifier("textkit-editor")
    textView.setAccessibilityValue(initialText)
    context.coordinator.textView = textView
    context.coordinator.observer = NotificationCenter.default.addObserver(
      forName: .synoraInsertAttachment, object: nil, queue: .main
    ) { [weak textView] _ in
      Task { @MainActor in textView?.insertProbeAttachment() }
    }
    DispatchQueue.main.async {
      let largeText = String(repeating: "中文🙂 e\u{301}\n", count: 12_500)
      let started = DispatchTime.now().uptimeNanoseconds
      let fixture = NSTextView(usingTextLayoutManager: true)
      fixture.frame = NSRect(x: 0, y: 0, width: 720, height: 480)
      fixture.string = largeText
      fixture.layoutSubtreeIfNeeded()
      metrics.record(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000)
      metrics.write(text: largeText, ranges: UTF16BlockAdapter(text: largeText).ranges)
    }
    return textView
  }

  func updateNSView(_ nsView: ProbeTextView, context: Context) {}

  static func dismantleNSView(_ nsView: ProbeTextView, coordinator: Coordinator) {
    if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
  }

  final class Coordinator {
    weak var textView: ProbeTextView?
    var observer: NSObjectProtocol?
  }
}
