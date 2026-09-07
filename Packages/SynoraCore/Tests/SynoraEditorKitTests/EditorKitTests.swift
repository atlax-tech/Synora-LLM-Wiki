import Foundation
import SynoraDomain
import Testing

@testable import SynoraEditorKit

@Test
func textStorageAdapterMapsUTF16RangesAndEditsOneBlock() throws {
  let recordID = UUID()
  let firstID = UUID()
  let secondID = UUID()
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(id: firstID, recordID: recordID, position: 0, text: "中文🙂"),
    Block(id: secondID, recordID: recordID, position: 1, text: "second"),
  ])
  let adapter = TextStorageAdapter(document: document)
  #expect(adapter.text == "中文🙂\nsecond")
  #expect(adapter.ranges.first?.range.length == ("中文🙂" as NSString).length)
  let updated = try adapter.applying(
    range: NSRange(location: 0, length: ("中文" as NSString).length), replacement: "日文")
  #expect(updated.block(id: firstID)?.text == "日文🙂")
  #expect(updated.block(id: secondID)?.text == "second")
}

@Test
func textStorageAdapterRejectsSplitComposedCharacterAndMarkdownShortcutsAreDeterministic() throws {
  let recordID = UUID()
  let blockID = UUID()
  let document = try BlockDocument(
    recordID: recordID,
    blocks: [Block(id: blockID, recordID: recordID, position: 0, text: "🙂")])
  let adapter = TextStorageAdapter(document: document)
  #expect(throws: EditorError.invalidSelection) {
    try adapter.applying(range: NSRange(location: 1, length: 0), replacement: "x")
  }
  #expect(MarkdownShortcut.block(for: "# 标题")?.type == .heading1)
  #expect(MarkdownShortcut.block(for: "# 标题")?.text == "标题")
  #expect(MarkdownShortcut.block(for: "plain") == nil)
}

@Test
func textStorageAdapterReplacesAcrossBlocksAndSessionUndoesIt() throws {
  let recordID = UUID()
  let firstID = UUID()
  let secondID = UUID()
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(id: firstID, recordID: recordID, position: 0, text: "one"),
    Block(id: secondID, recordID: recordID, position: 1, text: "two"),
  ])
  var session = EditorSession(document: document)
  let adapter = TextStorageAdapter(document: document)
  let start = NSMaxRange(adapter.ranges[0].range) - 1
  let end = adapter.ranges[1].range.location + 1
  let updated = try session.apply(
    range: NSRange(location: start, length: end - start), replacement: "X\nY")
  #expect(TextStorageAdapter(document: updated).text == "onX\nYwo")
  #expect(try session.undo() == document)
  #expect(try session.redo() == updated)
}
