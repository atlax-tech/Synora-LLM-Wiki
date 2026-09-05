import AppKit
import SwiftUI

struct TextKit2ProbeResult: Sendable {
  let text: String
  let blockRanges: [NSRange]
  let rangesValid: Bool

  static let fixture: Self = {
    let text = "中文输入🙂\nEnglish e\u{301}\n👩‍💻 attachment"
    let nsText = text as NSString
    let ranges = text.split(separator: "\n", omittingEmptySubsequences: false).reduce(
      into: (offset: 0, ranges: [NSRange]())
    ) { result, line in
      let length = (line as NSString).length
      result.ranges.append(NSRange(location: result.offset, length: length))
      result.offset += length + 1
    }.ranges
    let valid = ranges.enumerated().allSatisfy { index, range in
      let end = range.location + range.length
      guard range.location >= 0, end <= nsText.length else { return false }
      if index < ranges.count - 1 { return end <= ranges[index + 1].location }
      return true
    }
    return Self(text: text, blockRanges: ranges, rangesValid: valid)
  }()
}

struct TextKit2ProbeView: NSViewRepresentable {
  let initialText: String

  func makeNSView(context: Context) -> NSTextView {
    let textView = NSTextView(usingTextLayoutManager: true)
    textView.string = initialText
    textView.isRichText = false
    textView.isEditable = true
    textView.isSelectable = true
    textView.usesFindBar = true
    textView.textContainerInset = NSSize(width: 8, height: 8)
    textView.setAccessibilityLabel("TextKit 2 probe editor")
    return textView
  }

  func updateNSView(_ nsView: NSTextView, context: Context) {}
}
