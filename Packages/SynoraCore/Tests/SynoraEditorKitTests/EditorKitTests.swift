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
  let cachedAdapter = TextStorageAdapter(document: document, sourceText: adapter.text)
  #expect(adapter.text == "中文🙂\nsecond")
  #expect(cachedAdapter.text == adapter.text)
  #expect(cachedAdapter.ranges == adapter.ranges)
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
func textStorageAdapterIncludesNestedBlocksAndAdoptKeepsUndoHistory() throws {
  let recordID = UUID()
  let parentID = UUID()
  let childID = UUID()
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(id: parentID, recordID: recordID, position: 0, text: "parent", type: .toggle),
    Block(id: childID, recordID: recordID, position: 0, text: "child", parentID: parentID),
  ])
  #expect(TextStorageAdapter(document: document).text == "parent\nchild")

  var session = EditorSession(document: document)
  let edited = try session.apply(
    range: NSRange(location: 0, length: ("parent" as NSString).length), replacement: "updated")
  let mediaDocument = try edited.settingType(.callout, for: parentID)
  _ = session.adopt(mediaDocument)
  #expect(session.document.block(id: parentID)?.type == .callout)
  #expect(try session.undo() == edited)
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

@Test
func markdownAndSlashCommandsRespectMarkedCodeAndUndoBoundaries() throws {
  #expect(MarkdownShortcut.block(for: "# 标题", inCodeBlock: true) == nil)
  #expect(MarkdownShortcut.block(for: "# 标题", markedText: true) == nil)
  #expect(MarkdownShortcut.taskChecked(for: "- [x] 完成") == true)

  var menu = SlashMenuState(query: "/标题")
  #expect(menu.candidates == [.heading1, .heading2, .heading3])
  #expect(SlashCommand.matching("/标题") == [.heading1, .heading2, .heading3])
  _ = menu.moveSelection(by: 1)
  #expect(menu.selectedIndex == 1)
  let cancelled = menu.handle(.escape)
  #expect(cancelled == .cancelled)
  #expect(!menu.isPresented)
  var empty = SlashMenuState(query: "不存在")
  #expect(empty.candidates.isEmpty)
  #expect(empty.handle(.enter) == .none)
  empty.update(query: "代码")
  #expect(empty.candidates == [.code])

  let recordID = UUID()
  let blockID = UUID()
  let original = try BlockDocument(recordID: recordID, blocks: [
    Block(id: blockID, recordID: recordID, position: 0, text: "- [x] 完成"),
  ])
  var session = EditorSession(document: original)
  _ = try session.applyMarkdownShortcut(in: blockID)
  #expect(session.document.block(id: blockID)?.type == .task)
  #expect(session.document.block(id: blockID)?.text == "完成")
  #expect(session.document.block(id: blockID)?.attributes["checked"] == "true")
  _ = try session.undo()
  #expect(session.document == original)

  let slashID = UUID()
  session = EditorSession(document: try BlockDocument(recordID: recordID, blocks: [
    Block(id: slashID, recordID: recordID, position: 0, text: "/标题"),
  ]))
  _ = try session.applySlashCommand(.heading2, in: slashID)
  #expect(session.document.block(id: slashID)?.type == .heading2)
  #expect(session.document.block(id: slashID)?.text == "")

  let tableSlashID = UUID()
  session = EditorSession(document: try BlockDocument(recordID: recordID, blocks: [
    Block(id: tableSlashID, recordID: recordID, position: 0, text: "/table"),
  ]))
  _ = try session.applySlashCommand(.table, in: tableSlashID)
  #expect(session.document.block(id: tableSlashID)?.text == "")
  #expect(session.document.block(id: tableSlashID)?.content != nil)
}

@Test
func referencesUseStableIDsAndOnlyResolveLocalTargets() throws {
  let targetID = UUID(uuidString: "00000000-0000-4000-8000-0000000000a1")!
  let sourceRecordID = UUID()
  let sourceBlockID = UUID()
  let old = Record(id: targetID, title: "旧名称")
  let candidates = ReferenceParser.candidates(for: "旧", records: [old])
  #expect(candidates.count == 1)
  #expect(candidates[0].token(using: .mention) == "@[\(targetID.uuidString)]")

  let text = "see [[\(targetID.uuidString)]] @[\(targetID.uuidString)]"
  let references = ReferenceParser.references(in: text)
  #expect(references.count == 2)
  #expect(references.map(\.syntax) == [.wikiLink, .mention])
  #expect(ReferenceParser.targetID(atUTF16Offset: references[0].range.location + 3, in: text) == targetID)
  #expect(ReferenceParser.candidates(for: "", records: []).isEmpty)
  let renamed = ReferenceParser.candidates(for: "新", records: [Record(id: targetID, title: "新名称")])
  #expect(ReferenceParser.resolve(references[0], in: renamed)?.title == "新名称")
  #expect(ReferenceParser.resolve(references[0], in: []) == nil)

  let source = try BlockDocument(recordID: sourceRecordID, blocks: [
    Block(
      id: sourceBlockID,
      recordID: sourceRecordID,
      position: 0,
      text: "引用："),
  ])
  #expect(ReferenceParser.backlinks(to: targetID, in: [source]).isEmpty)
  var session = EditorSession(document: source)
  _ = try session.insertReference(
    candidates[0], in: sourceBlockID, atUTF16Offset: ("引用：" as NSString).length)
  #expect(session.document.block(id: sourceBlockID)?.text == "引用：[[\(targetID.uuidString)]]")
  _ = try session.undo()
  #expect(session.document == source)
}

@Test
func formattingBarHandlesMixedCrossBlockSelectionAndUndo() throws {
  let recordID = UUID()
  let firstID = UUID()
  let secondID = UUID()
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(id: firstID, recordID: recordID, position: 0, text: "你好"),
    Block(id: secondID, recordID: recordID, position: 1, text: "世界"),
  ])
  var session = EditorSession(document: document)
  let selection = NSRange(location: 1, length: 3)
  #expect(!session.formattingState(for: NSRange(location: 0, length: 0)).isPresented)
  _ = try session.applyFormatting(.bold, in: selection)
  #expect(session.document.block(id: firstID)?.inlineAttributes == [
    InlineAttribute(range: NSRange(location: 1, length: 1), style: .bold),
  ])
  #expect(session.document.block(id: secondID)?.inlineAttributes == [
    InlineAttribute(range: NSRange(location: 0, length: 1), style: .bold),
  ])
  #expect(session.formattingState(for: selection).activeStyles == [.bold])
  #expect(throws: EditorError.invalidURL) {
    try session.applyFormatting(.link, in: selection, linkURL: "javascript:alert(1)")
  }
  _ = try session.applyFormatting(.link, in: selection, linkURL: "https://example.com")
  #expect(session.document.block(id: firstID)?.inlineAttributes.contains {
    $0.style == .link && $0.value == "https://example.com"
  } == true)
  #expect(try JSONDecoder().decode(
    BlockDocument.self,
    from: JSONEncoder().encode(session.document)) == session.document)
  _ = try session.undo()
  #expect(session.document.block(id: firstID)?.inlineAttributes.count == 1)
  _ = try session.undo()
  #expect(session.document == document)
}

@Test
func findReplaceSupportsChineseAndOneUndoGroup() throws {
  let recordID = UUID()
  let firstID = UUID()
  let secondID = UUID()
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(id: firstID, recordID: recordID, position: 0, text: "苹果苹果"),
    Block(id: secondID, recordID: recordID, position: 1, text: "苹果"),
  ])
  #expect(TextSearch.matches(in: document, query: "苹果").count == 3)
  var session = EditorSession(document: document)
  _ = try session.replaceAll(query: "苹果", with: "香蕉")
  #expect(TextStorageAdapter(document: session.document).text == "香蕉香蕉\n香蕉")
  _ = try session.undo()
  #expect(session.document == document)
  #expect(throws: EditorError.emptyQuery) {
    try session.replaceAll(query: "", with: "ignored")
  }
}

@Test
func pastePreservesSafeRichTextSanitizesHTMLAndKeepsFilesForAssetPipeline() throws {
  let recordID = UUID()
  let blockID = UUID()
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(id: blockID, recordID: recordID, position: 0, text: "")
  ])
  var session = EditorSession(document: document)
  let rich = RichTextFragment(
    text: "加粗",
    inlineAttributes: [InlineAttribute(
      range: NSRange(location: 0, length: ("加粗" as NSString).length), style: .bold)])
  _ = try session.paste(.richText(rich), at: NSRange(location: 0, length: 0))
  #expect(session.document.block(id: blockID)?.text == "加粗")
  #expect(session.document.block(id: blockID)?.inlineAttributes.first?.style == .bold)
  _ = try session.undo()
  #expect(session.document == document)

  let html = "<p>A</p><script>window.evil=1</script><p>B &amp; C</p>"
  #expect(HTMLPasteSanitizer.plainText(html) == "A\nB & C")
  let prepared = try session.preparePaste(.files([URL(fileURLWithPath: "/tmp/example.pdf")]))
  #expect(prepared.fileURLs == [URL(fileURLWithPath: "/tmp/example.pdf")])
  #expect(throws: EditorError.invalidPaste) {
    try session.preparePaste(.richText(RichTextFragment(
      text: "bad", inlineAttributes: [InlineAttribute(
        range: NSRange(location: 0, length: 4), style: .bold)])))
  }
}

@Test
func assetPlacementCommandsCommitAndUndoAsOneEdit() throws {
  let recordID = UUID()
  let blockID = UUID()
  let assetID = UUID()
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(id: blockID, recordID: recordID, position: 0, text: "", type: .image)
  ])
  var session = EditorSession(document: document)
  _ = try session.placeAsset(
    AssetPlacement(assetID: assetID, caption: "封面"), in: blockID)
  #expect(session.document.assetPlacements(in: blockID) == [
    AssetPlacement(assetID: assetID, caption: "封面")
  ])
  _ = try session.undo()
  #expect(session.document == document)

  _ = try session.placeAsset(AssetPlacement(assetID: assetID), in: blockID)
  _ = try session.removeAsset(assetID, from: blockID)
  #expect(session.document.assetPlacements(in: blockID).isEmpty)
  _ = try session.undo()
  #expect(session.document.assetPlacements(in: blockID).map(\.assetID) == [assetID])
}

@Test
func mediaCommandsGroupLayoutCaptionCropReorderReplaceAndLinkUndo() throws {
  let recordID = UUID()
  let blockID = UUID()
  let firstID = UUID()
  let secondID = UUID()
  let replacementID = UUID()
  let document = try BlockDocument(recordID: recordID).creatingMedia(
    .gallery,
    assetIDs: [firstID, secondID],
    id: blockID)
  var session = EditorSession(document: document)

  _ = try session.setMediaLayout(.collage, in: blockID)
  _ = try session.setAssetCaption("封面", for: firstID, in: blockID)
  _ = try session.setAssetCrop(["x": 0.25, "width": 0.5], for: firstID, in: blockID)
  _ = try session.reorderAsset(firstID, in: blockID)
  _ = try session.replaceAsset(
    secondID,
    with: AssetPlacement(assetID: replacementID, caption: "新文件"),
    in: blockID)
  #expect(session.document.assetPlacements(in: blockID).map(\.assetID) == [replacementID, firstID])
  #expect(session.document.block(id: blockID)?.mediaLayout == .collage)

  _ = try session.undo()
  #expect(session.document.assetPlacements(in: blockID).map(\.assetID) == [secondID, firstID])
  _ = try session.undo()
  _ = try session.undo()
  _ = try session.undo()
  _ = try session.undo()
  #expect(session.document == document)

  let linkID = UUID()
  let linkDocument = try BlockDocument(recordID: recordID).creatingLink(
    LinkCard(url: "https://example.com"), id: linkID)
  session = EditorSession(document: linkDocument)
  _ = try session.setLinkCard(LinkCard(url: "https://example.com", title: "Example"), in: linkID)
  #expect(session.document.block(id: linkID)?.content == .link(
    LinkCard(url: "https://example.com", title: "Example")))
  _ = try session.undo()
  #expect(session.document == linkDocument)
}
