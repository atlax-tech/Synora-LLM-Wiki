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

@Test
func markdownSlashReferencesAndPasteRemainDeterministic() {
  #expect(MarkdownShortcut.block(for: "12. item")?.type == .numberedList)
  #expect(MarkdownShortcut.block(for: "```swift")?.type == .code)
  #expect(MarkdownShortcut.block(for: "---")?.text == "")
  #expect(SlashCommand.matching("head").map(\.blockType) == [.heading1, .heading2, .heading3])
  let id = UUID(uuidString: "00000000-0000-4000-8000-000000000099")!
  let references = ReferenceParser.recordReferences(in: "see [[\(id.uuidString)]]")
  #expect(references.count == 1)
  #expect(references[0].targetID == id)
  #expect(HTMLPasteSanitizer.plainText("<p>A</p><p>B &amp; C</p>") == "A\nB & C")
}

@Test
func basicEditorReturnBackspaceAndUndoFollowBlockRules() throws {
  let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000050")!
  let firstID = UUID(uuidString: "00000000-0000-4000-8000-000000000051")!
  let secondID = UUID(uuidString: "00000000-0000-4000-8000-000000000052")!
  let splitID = UUID(uuidString: "00000000-0000-4000-8000-000000000053")!
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(id: firstID, recordID: recordID, position: 0, text: "标题", type: .heading1),
    Block(id: secondID, recordID: recordID, position: 1, text: "正文", type: .paragraph),
  ])
  var session = EditorSession(document: document)

  _ = try session.pressReturn(
    in: firstID, atUTF16Offset: ("标" as NSString).length, newID: splitID)
  #expect(session.document.children().map(\.id) == [firstID, splitID, secondID])
  #expect(session.document.block(id: splitID)?.type == .heading1)
  #expect(session.document.block(id: firstID)?.text == "标")
  #expect(session.document.block(id: splitID)?.text == "题")

  _ = try session.pressBackspace(in: splitID, atUTF16Offset: 0)
  #expect(session.document.children().map(\.id) == [firstID, secondID])
  #expect(session.document.block(id: firstID)?.text == "标题")
  _ = try session.undo()
  #expect(session.document.children().map(\.id) == [firstID, splitID, secondID])
  _ = try session.redo()
  #expect(session.document.children().map(\.id) == [firstID, secondID])
}

@Test
func emptyListReturnExitsToParagraphAndBackspaceDeletesDivider() throws {
  let recordID = UUID()
  let listID = UUID()
  let dividerID = UUID()
  var session = EditorSession(document: try BlockDocument(recordID: recordID, blocks: [
    Block(id: listID, recordID: recordID, position: 0, text: "", type: .bulletedList),
    Block(id: dividerID, recordID: recordID, position: 1, text: "", type: .divider),
  ]))

  _ = try session.pressReturn(in: listID, atUTF16Offset: 0)
  #expect(session.document.block(id: listID)?.type == .paragraph)
  let paragraphID = UUID(uuidString: "00000000-0000-4000-8000-000000000054")!
  _ = try session.pressReturn(in: dividerID, atUTF16Offset: 0, newID: paragraphID)
  #expect(session.document.children().map(\.id) == [listID, dividerID, paragraphID])
  _ = try session.pressBackspace(in: dividerID, atUTF16Offset: 0)
  #expect(session.document.children().map(\.id) == [listID, paragraphID])
}

@Test
func backspaceRejectsComposedCharacterInterior() throws {
  let recordID = UUID()
  let blockID = UUID()
  var session = EditorSession(document: try BlockDocument(recordID: recordID, blocks: [
    Block(id: blockID, recordID: recordID, position: 0, text: "🙂", type: .paragraph),
  ]))
  #expect(throws: EditorError.invalidSelection) {
    try session.pressBackspace(in: blockID, atUTF16Offset: 1)
  }
  #expect(session.document.block(id: blockID)?.text == "🙂")
}

@Test
func crossTypeSelectionKeepsEachBlockStructure() throws {
  let recordID = UUID()
  let headingID = UUID()
  let codeID = UUID()
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(id: headingID, recordID: recordID, position: 0, text: "标题", type: .heading2),
    Block(id: codeID, recordID: recordID, position: 1, text: "代码", type: .code),
  ])
  let adapter = TextStorageAdapter(document: document)
  var session = EditorSession(document: document)
  let start = adapter.ranges[0].range.location
  let end = NSMaxRange(adapter.ranges[1].range)
  _ = try session.apply(range: NSRange(location: start, length: end - start), replacement: "新标题\n新代码")
  #expect(session.document.block(id: headingID)?.type == .heading2)
  #expect(session.document.block(id: codeID)?.type == .code)
  #expect(session.document.block(id: headingID)?.text == "新标题")
  #expect(session.document.block(id: codeID)?.text == "新代码")
}

@Test
func advancedEditorEditsTablesNavigatesAndRestoresCollapsedFocus() throws {
  let recordID = UUID()
  let tableID = UUID()
  let toggleID = UUID()
  let childID = UUID()
  let calloutID = UUID()
  var session = EditorSession(document: try BlockDocument(recordID: recordID, blocks: [
    Block(
      id: tableID, recordID: recordID, position: 0, text: "", type: .table,
      content: .table(TableContent(rows: [
        [TableCell(text: "A"), TableCell(text: "B")],
        [TableCell(text: "C"), TableCell(text: "D")],
      ]))),
    Block(id: toggleID, recordID: recordID, position: 1, text: "详情", type: .toggle),
    Block(id: childID, recordID: recordID, position: 0, text: "长文本", parentID: toggleID),
    Block(id: calloutID, recordID: recordID, position: 2, text: "提示", type: .callout),
  ]))

  _ = try session.editTableCell(in: tableID, row: 1, column: 1, text: "改过")
  #expect(session.tableCell(in: tableID, row: 1, column: 1)?.text == "改过")
  #expect(try session.navigateTable(
    in: tableID,
    from: TableCellPosition(row: 0, column: 0),
    direction: .next) == TableCellPosition(row: 0, column: 1))
  #expect(try session.pressTab(
    in: tableID,
    from: TableCellPosition(row: 1, column: 1)) == TableCellPosition(row: 2, column: 0))
  #expect(session.tableCell(in: tableID, row: 2, column: 0) != nil)

  try session.focus(on: childID, atUTF16Offset: 2)
  _ = try session.toggleCollapse(in: toggleID)
  #expect(session.focus?.blockID == toggleID)
  #expect(TextStorageAdapter(document: session.document).ranges.map(\.blockID)
    == [tableID, toggleID, calloutID])
  _ = try session.toggleCollapse(in: toggleID)
  #expect(session.focus == EditorFocus(blockID: childID, utf16Offset: 2))

  _ = try session.setCalloutStyle(.warning, in: calloutID)
  #expect(session.document.block(id: calloutID)?.calloutStyle == .warning)
  #expect(throws: BlockTreeError.invalidChild(toggleID)) {
    try session.execute(.setCalloutStyle(.info), blockID: toggleID)
  }
  _ = try session.undo()
  #expect(session.focus?.blockID == childID)
}
