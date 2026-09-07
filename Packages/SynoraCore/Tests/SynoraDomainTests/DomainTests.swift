import Foundation
import Testing

@testable import SynoraDomain

@Test
func fixedIDsAndRevisionAreDeterministic() throws {
  let first = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
  let second = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
  let generator = FixedIDGenerator([first, second])
  #expect(generator.next() == first)
  #expect(generator.next() == second)
  #expect(try Revision.next(after: 0, expected: 0) == 1)
  #expect(throws: RevisionError.stale(expected: 0, actual: 1)) {
    try Revision.next(after: 1, expected: 0)
  }
}

@Test
func uuidGeneratorProducesVersionFourUniqueIDs() {
  let generator = UUIDGenerator()
  let ids = (0..<10_000).map { _ in generator.next() }
  #expect(Set(ids).count == ids.count)
  #expect(
    ids.allSatisfy { uuid in
      withUnsafeBytes(of: uuid.uuid) { bytes in
        bytes[6] >> 4 == 4 && bytes[8] & 0xC0 == 0x80
      }
    })
}

@Test
func operationHashUsesCanonicalBytes() {
  let id = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
  let entity = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
  let timestamp = Date(timeIntervalSince1970: 1)
  let left = Operation(
    id: id,
    transactionID: 1,
    sequence: 1,
    entityID: entity,
    entityRevision: 1,
    kind: "record.save",
    payload: Data("{}".utf8),
    timestamp: timestamp,
    previousHash: nil
  )
  let right = Operation(
    id: id,
    transactionID: 1,
    sequence: 1,
    entityID: entity,
    entityRevision: 1,
    kind: "record.save",
    payload: Data("{}".utf8),
    timestamp: timestamp,
    previousHash: nil
  )
  #expect(left.canonicalBytes == right.canonicalBytes)
  #expect(left.hash == right.hash)
  #expect(
    String(decoding: left.canonicalBytes, as: UTF8.self)
      == "{\"entityID\":\"00000000-0000-4000-8000-000000000002\",\"entityRevision\":1,\"id\":\"00000000-0000-4000-8000-000000000001\",\"kind\":\"record.save\",\"payload\":\"e30=\",\"previousHash\":null,\"sequence\":1,\"timestamp\":1,\"transactionID\":1}"
  )
  #expect(left.hash == "3f23cfd87d3fb1d6333e02fde4f1b7eb8ef9b18997d0b05b6179128ec899ef86")
}

@Test
func blockDocumentPreservesIdentityOrderingAndUnknownFields() throws {
  let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000010")!
  let firstID = UUID(uuidString: "00000000-0000-4000-8000-000000000011")!
  let secondID = UUID(uuidString: "00000000-0000-4000-8000-000000000012")!
  let first = Block(
    id: firstID, recordID: recordID, position: 0, text: "中文🙂",
    type: .bulletedList, unknownFields: ["future": .object(["enabled": .bool(true)])])
  let second = Block(
    id: secondID, recordID: recordID, position: 1, text: "子项", parentID: firstID,
    type: .paragraph)
  let document = try BlockDocument(recordID: recordID, blocks: [first, second])

  #expect(document.children().map(\.id) == [firstID])
  #expect(document.descendants(of: firstID).map(\.id) == [secondID])
  let encoded = try JSONEncoder().encode(document)
  let decoded = try JSONDecoder().decode(BlockDocument.self, from: encoded)
  #expect(decoded == document)
}

@Test
func blockDocumentRejectsInvalidParentsAndCycles() throws {
  let recordID = UUID()
  let parentID = UUID()
  let childID = UUID()
  #expect(throws: BlockTreeError.invalidChild(childID)) {
    try BlockDocument(
      recordID: recordID,
      blocks: [
        Block(id: parentID, recordID: recordID, position: 0, text: "plain"),
        Block(id: childID, recordID: recordID, position: 1, text: "child", parentID: parentID),
      ])
  }
  #expect(throws: BlockTreeError.missingParent(parentID)) {
    try BlockDocument(
      recordID: recordID,
      blocks: [Block(id: childID, recordID: recordID, position: 0, text: "child", parentID: parentID)])
  }
}

@Test
func legacyBlockPayloadDecodesWithParagraphDefaults() throws {
  let id = UUID(uuidString: "00000000-0000-4000-8000-000000000020")!
  let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000021")!
  let data = Data("{\"id\":\"\(id.uuidString)\",\"recordID\":\"\(recordID.uuidString)\",\"position\":2,\"text\":\"legacy\",\"revision\":3}".utf8)
  let block = try JSONDecoder().decode(Block.self, from: data)
  #expect(block.type == .paragraph)
  #expect(block.orderKey == 2048)
}

@Test
func blockDocumentEditingPreservesSplitAndMergeIdentity() throws {
  let recordID = UUID()
  let firstID = UUID()
  let secondID = UUID()
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(id: firstID, recordID: recordID, position: 0, text: "中文🙂"),
    Block(id: secondID, recordID: recordID, position: 1, text: "尾段"),
  ])
  let splitID = UUID()
  let split = try document.splitting(
    id: firstID, atUTF16Offset: ("中文" as NSString).length, newID: splitID)
  #expect(split.children().map(\.id) == [firstID, splitID, secondID])
  #expect(split.block(id: firstID)?.text == "中文")
  #expect(split.block(id: splitID)?.text == "🙂")
  let merged = try split.merging(id: firstID, with: splitID)
  #expect(merged.children().map(\.id) == [firstID, secondID])
  #expect(merged.block(id: firstID)?.text == "中文🙂")
}

@Test
func blockDocumentIndentOutdentAndTaskToggleUseTreeRules() throws {
  let recordID = UUID()
  let parentID = UUID()
  let childID = UUID()
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(id: childID, recordID: recordID, position: 1, text: "child"),
    Block(id: parentID, recordID: recordID, position: 0, text: "parent", type: .toggle),
  ])
  let indented = try document.indenting(id: childID, under: parentID)
  #expect(indented.block(id: childID)?.parentID == parentID)
  #expect(try indented.outdenting(id: childID).block(id: childID)?.parentID == nil)
  let task = try document.settingType(.task, for: childID)
  #expect(task.block(id: childID)?.attributes["checked"] == "false")
  #expect(try task.togglingTask(id: childID).block(id: childID)?.attributes["checked"] == "true")
}

@Test
func structuredBlockContentRoundTripsAndTableEditsStayRectangular() throws {
  let recordID = UUID()
  let blockID = UUID()
  let assetID = UUID()
  var table = TableContent(rows: [[TableCell(text: "A")]])
  table.insertColumn()
  table.insertRow()
  #expect(table.rows.count == 2)
  #expect(table.columnCount == 2)
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(
      id: blockID, recordID: recordID, position: 0, text: "",
      type: .table,
      content: .table(table)),
    Block(
      id: UUID(), recordID: recordID, position: 1, text: "photo",
      type: .image,
      content: .assets([AssetPlacement(assetID: assetID, caption: "说明")]))
  ])
  let decoded = try JSONDecoder().decode(BlockDocument.self, from: JSONEncoder().encode(document))
  #expect(decoded == document)
}

@Test
func assetPlacementsStayOnMediaBlocksAndKeepOrder() throws {
  let recordID = UUID()
  let blockID = UUID()
  let firstAssetID = UUID()
  let secondAssetID = UUID()
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(id: blockID, recordID: recordID, position: 0, text: "", type: .gallery)
  ])

  let first = try document.placingAsset(
    AssetPlacement(assetID: firstAssetID, caption: "one"), in: blockID)
  let second = try first.placingAsset(
    AssetPlacement(assetID: secondAssetID, caption: "two"), in: blockID)
  #expect(second.assetPlacements(in: blockID).map(\.assetID) == [firstAssetID, secondAssetID])
  #expect(second.assetPlacements(in: blockID).map(\.order) == [0, 1])
  let removed = try second.removingAsset(firstAssetID, from: blockID)
  #expect(removed.assetPlacements(in: blockID).map(\.assetID) == [secondAssetID])
  let paragraph = try BlockDocument(recordID: recordID, blocks: [
    Block(id: blockID, recordID: recordID, position: 0, text: "text")
  ])
  #expect(throws: BlockTreeError.invalidChild(blockID)) {
    try paragraph.placingAsset(AssetPlacement(assetID: firstAssetID), in: blockID)
  }
  #expect(throws: BlockTreeError.invalidChild(blockID)) {
    try BlockDocument(recordID: recordID, blocks: [
      Block(
        id: blockID, recordID: recordID, position: 0, text: "text",
        content: .assets([AssetPlacement(assetID: firstAssetID)]))
    ])
  }
}

@Test
func mediaBlocksSupportLayoutsCaptionsCropReorderAndReplacement() throws {
  let recordID = UUID()
  let blockID = UUID()
  let firstID = UUID()
  let secondID = UUID()
  let thirdID = UUID()
  var document = try BlockDocument(recordID: recordID).creatingMedia(
    .gallery,
    assetIDs: [firstID, secondID],
    layout: .collage,
    id: blockID)
  #expect(document.block(id: blockID)?.mediaLayout == .collage)
  #expect(document.assetPlacements(in: blockID).map(\.assetID) == [firstID, secondID])

  document = try document.settingAssetCaption("主图", for: firstID, in: blockID)
  document = try document.settingAssetCrop(
    ["x": 0.1, "y": 0.2, "width": 0.8, "height": 0.7],
    for: firstID,
    in: blockID)
  document = try document.reorderingAsset(firstID, in: blockID)
  #expect(document.assetPlacements(in: blockID).map(\.assetID) == [secondID, firstID])
  #expect(document.assetPlacement(firstID, in: blockID)?.caption == "主图")
  #expect(document.assetPlacement(firstID, in: blockID)?.crop["width"] == 0.8)

  document = try document.replacingAsset(
    secondID,
    with: AssetPlacement(assetID: thirdID, caption: "替换"),
    in: blockID)
  #expect(document.assetPlacements(in: blockID).map(\.assetID) == [thirdID, firstID])
  #expect(document.assetPlacement(thirdID, in: blockID)?.caption == "替换")

  let image = try BlockDocument(recordID: recordID).creatingMedia(.image, assetIDs: [firstID])
  #expect(throws: BlockTreeError.invalidChild(image.children()[0].id)) {
    try image.placingAsset(AssetPlacement(assetID: secondID), in: image.children()[0].id)
  }
  #expect(throws: BlockTreeError.invalidChild(blockID)) {
    try document.settingAssetCrop(["width": 2], for: firstID, in: blockID)
  }
}

@Test
func linkCardsValidateURLAndPreserveTypedContent() throws {
  let recordID = UUID()
  let blockID = UUID()
  let card = LinkCard(url: "https://example.com", title: "Example")
  let document = try BlockDocument(recordID: recordID).creatingLink(card, id: blockID)
  #expect(document.block(id: blockID)?.content == .link(card))
  #expect(throws: BlockTreeError.invalidChild(blockID)) {
    try document.settingLinkCard(LinkCard(url: "javascript:alert(1)"), for: blockID)
  }
  let invalidID = UUID()
  #expect(throws: BlockTreeError.invalidChild(invalidID)) {
    try BlockDocument(recordID: recordID).creatingLink(
      LinkCard(url: "not a url"), id: invalidID)
  }
}

@Test
func advancedBlocksEditTablesAndKeepContainerRules() throws {
  let recordID = UUID()
  let tableID = UUID()
  var table = TableContent(rows: [
    [TableCell(text: "A"), TableCell(text: "B")],
    [TableCell(text: "C")],
  ])
  #expect(table.isRectangular)
  #expect(table.cell(atRow: 1, column: 1)?.text == "")
  let edited = table.editingCell(atRow: 1, column: 1, text: "D")
  #expect(edited)
  #expect(table.navigating(from: TableCellPosition(row: 0, column: 1), direction: .next)
    == TableCellPosition(row: 1, column: 0))
  table.removeColumn(at: 1)
  table.insertRow()
  #expect(table.rows.count == 3)
  #expect(table.columnCount == 1)

  var document = try BlockDocument(recordID: recordID, blocks: [
    Block(
      id: tableID, recordID: recordID, position: 0, text: "", type: .table,
      content: .table(table)),
  ])
  document = try document.editingTableCell(id: tableID, row: 0, column: 0, text: "edited")
  #expect(document.block(id: tableID)?.content == .table(TableContent(rows: [
    [TableCell(text: "edited")],
    [TableCell(text: "C")],
    [TableCell()],
  ])))
  document = try document.insertingTableColumn(id: tableID)
  #expect((document.block(id: tableID)?.content).map { content in
    if case .table(let table) = content { return table.isRectangular }
    return false
  } == true)

  let toggleID = UUID()
  let childID = UUID()
  let calloutID = UUID()
  let nested = try BlockDocument(recordID: recordID, blocks: [
    Block(id: toggleID, recordID: recordID, position: 1, text: "展开", type: .toggle),
    Block(id: childID, recordID: recordID, position: 0, text: "内容", parentID: toggleID),
    Block(id: calloutID, recordID: recordID, position: 2, text: "提醒", type: .callout),
  ])
  #expect(nested.block(id: toggleID)?.isCollapsed == false)
  #expect(try nested.togglingCollapse(id: toggleID).block(id: toggleID)?.isCollapsed == true)
  #expect(nested.block(id: calloutID)?.calloutStyle == .info)
  #expect(try nested.settingCalloutStyle(.warning, for: calloutID)
    .block(id: calloutID)?.calloutStyle == .warning)
  #expect(throws: BlockTreeError.invalidChild(childID)) {
    try BlockDocument(recordID: recordID, blocks: [
      Block(id: tableID, recordID: recordID, position: 0, text: "", type: .table),
      Block(id: childID, recordID: recordID, position: 0, text: "非法", parentID: tableID),
    ])
  }
}

@Test
func basicBlockKindsCreateEditConvertAndExposeListState() throws {
  let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000030")!
  var document = try BlockDocument(recordID: recordID)
  let paragraphID = UUID(uuidString: "00000000-0000-4000-8000-000000000031")!
  let headingID = UUID(uuidString: "00000000-0000-4000-8000-000000000032")!
  let firstNumberID = UUID(uuidString: "00000000-0000-4000-8000-000000000033")!
  let secondNumberID = UUID(uuidString: "00000000-0000-4000-8000-000000000034")!
  let taskID = UUID(uuidString: "00000000-0000-4000-8000-000000000035")!
  let quoteID = UUID(uuidString: "00000000-0000-4000-8000-000000000036")!
  let codeID = UUID(uuidString: "00000000-0000-4000-8000-000000000037")!
  let dividerID = UUID(uuidString: "00000000-0000-4000-8000-000000000038")!

  document = try document.creating(.paragraph, text: "正文", id: paragraphID)
  document = try document.creating(.heading2, text: "标题", id: headingID)
  document = try document.creating(.numberedList, text: "第一项", id: firstNumberID)
  document = try document.creating(.numberedList, text: "第二项", id: secondNumberID)
  document = try document.creating(.task, text: "待办", id: taskID)
  document = try document.creating(.quote, text: "引用", id: quoteID)
  document = try document.creating(.code, text: "let value = 1", id: codeID)
  document = try document.creating(.divider, text: "被忽略", id: dividerID)

  #expect(document.block(id: taskID)?.attributes["checked"] == "false")
  #expect(document.block(id: dividerID)?.text == "")
  #expect(document.listNumber(for: firstNumberID) == 1)
  #expect(document.listNumber(for: secondNumberID) == 2)
  #expect(document.block(id: taskID)?.accessibilityDescription == "Unchecked task: 待办")

  document = try document.editing(id: codeID, text: "print(\"中文\")")
  #expect(document.block(id: codeID)?.text == "print(\"中文\")")
  document = try document.settingType(.task, for: paragraphID)
  #expect(document.block(id: paragraphID)?.attributes["checked"] == "false")
  #expect(try document.togglingTask(id: paragraphID).block(id: paragraphID)?.accessibilityDescription == "Completed task: 正文")
  document = try document.settingType(.paragraph, for: paragraphID)
  #expect(document.block(id: paragraphID)?.attributes["checked"] == nil)
}

@Test
func basicBlockCopyPastePreservesSubtreeAndRejectsCycles() throws {
  let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000040")!
  let parentID = UUID(uuidString: "00000000-0000-4000-8000-000000000041")!
  let childID = UUID(uuidString: "00000000-0000-4000-8000-000000000042")!
  var document = try BlockDocument(recordID: recordID, blocks: [
    Block(id: parentID, recordID: recordID, position: 0, text: "项目", type: .bulletedList),
    Block(id: childID, recordID: recordID, position: 0, text: "子项", parentID: parentID),
  ])
  let clipboard = try document.copying(ids: [parentID])
  let pastedIDs = [
    UUID(uuidString: "00000000-0000-4000-8000-000000000043")!,
    UUID(uuidString: "00000000-0000-4000-8000-000000000044")!,
  ]
  document = try document.pasting(
    clipboard,
    idGenerator: FixedIDGenerator(pastedIDs))
  #expect(document.children().map(\.id) == [parentID, pastedIDs[0]])
  #expect(document.block(id: pastedIDs[0])?.text == "项目")
  #expect(document.block(id: pastedIDs[1])?.parentID == pastedIDs[0])
  #expect(document.block(id: childID)?.parentID == parentID)
  #expect(throws: BlockTreeError.cycle(parentID)) {
    try document.moving(id: parentID, to: childID)
  }
  let missingSiblingID = UUID()
  #expect(throws: BlockTreeError.missingSibling(missingSiblingID)) {
    try document.creating(.paragraph, before: missingSiblingID)
  }
}

@Test
func insertingWithNoOrderGapReindexesOnlyTheTargetSiblingGroup() throws {
  let recordID = UUID()
  let firstID = UUID()
  let secondID = UUID()
  let containerID = UUID()
  let childID = UUID()
  let insertedID = UUID()
  var document = try BlockDocument(recordID: recordID, blocks: [
    Block(id: firstID, recordID: recordID, position: 0, text: "A", orderKey: 0),
    Block(id: secondID, recordID: recordID, position: 1, text: "B", orderKey: 1),
    Block(id: containerID, recordID: recordID, position: 2, text: "容器", type: .toggle, orderKey: 2048),
    Block(id: childID, recordID: recordID, position: 0, text: "子项", parentID: containerID, orderKey: 7),
  ])
  document = try document.creating(.paragraph, text: "中间", before: secondID, id: insertedID)
  #expect(document.children().map(\.id) == [firstID, insertedID, secondID, containerID])
  #expect(document.children(of: containerID).first?.orderKey == 7)
  #expect(document.block(id: insertedID)?.orderKey == 1024)
}
