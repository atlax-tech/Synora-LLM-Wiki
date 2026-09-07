import Foundation
import Testing

@testable import SynoraExport
import SynoraDomain
import SynoraAssets

@Test
func recordExportPackageRoundTripsIDsUnknownFieldsAndChecksums() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-export-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let recordID = UUID()
  let parentID = UUID()
  let record = Record(
    id: recordID,
    title: "可读标题",
    kind: .journal,
    journalDate: Date(timeIntervalSince1970: 10),
    metadata: ["mood": "calm"],
    unknownFields: ["future": .string("keep")]
  )
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(
      id: parentID,
      recordID: recordID,
      position: 0,
      text: "正文🙂",
      type: .callout,
      attributes: ["tone": "blue"],
      unknownFields: ["x": .number(1)]),
    Block(id: UUID(), recordID: recordID, position: 0, text: "子项", parentID: parentID),
  ])
  let service = RecordExportService()
  let packageURL = root.appendingPathComponent("record.synora")
  _ = try service.exportPackage(record: record, document: document, to: packageURL)
  let imported = try service.importPackage(from: packageURL)
  #expect(imported.record == record)
  #expect(imported.document == document)
  #expect(try service.markdown(record: record, document: document).contains("正文🙂"))
  #expect(try service.html(record: record, document: document).contains("可读标题"))
  #expect(throws: ExportError.idConflict(recordID)) {
    try service.importPackage(from: packageURL, existingRecordIDs: [recordID])
  }
}

@Test
func externalMarkdownImportKeepsVisibleTextAndRejectsTampering() throws {
  let service = RecordExportService()
  let imported = try service.importMarkdown("# 标题\n\n第一行\n第二行", kind: .note)
  #expect(imported.record.title == "标题")
  #expect(imported.document.blocks.first?.text == "第一行\n第二行")

  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-export-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let recordID = UUID()
  let record = Record(id: recordID, title: "One")
  let document = try BlockDocument(recordID: recordID)
  let packageURL = root.appendingPathComponent("record.synora")
  _ = try service.exportPackage(record: record, document: document, to: packageURL)
  let contentURL = packageURL.appendingPathComponent("records/\(recordID.uuidString)/content.md")
  try Data("tampered".utf8).write(to: contentURL)
  #expect(throws: ExportError.checksumMismatch("records/\(recordID.uuidString)/content.md")) {
    try service.importPackage(from: packageURL)
  }
}

@Test
func readableExportsRoundTripMetadataStructureAndAllContentKinds() throws {
  let recordID = UUID()
  let parentID = UUID()
  let imageID = UUID()
  let record = Record(
    id: recordID,
    title: "结构🙂",
    kind: .journal,
    journalDate: Date(timeIntervalSince1970: 123),
    metadata: ["tag": "p2"],
    unknownFields: ["future": .bool(true)])
  let blocks = [
    Block(
      id: parentID,
      recordID: recordID,
      position: 0,
      text: "Callout",
      type: .callout,
      inlineAttributes: [InlineAttribute(range: NSRange(location: 0, length: 4), style: .bold)],
      attributes: ["calloutStyle": "warning"],
      unknownFields: ["vendor": .string("keep")]),
    Block(
      id: UUID(), recordID: recordID, position: 0, text: "Cell",
      parentID: parentID, type: .paragraph),
    Block(
      id: imageID, recordID: recordID, position: 1, text: "",
      type: .image,
      content: .assets([AssetPlacement(assetID: UUID(), caption: "crop", crop: ["x": 0.5])])),
    Block(
      id: UUID(), recordID: recordID, position: 2, text: "Links",
      type: .link, content: .link(LinkCard(url: "https://example.com", title: "Example"))),
    Block(
      id: UUID(), recordID: recordID, position: 3, text: "Table",
      type: .table, content: .table(TableContent(rows: [[TableCell(text: "A")]]))),
    Block(
      id: UUID(), recordID: recordID, position: 4, text: "Future",
      type: .unknown("vendor-block"), content: .raw(.object(["x": .number(1)]))),
  ]
  let document = try BlockDocument(recordID: recordID, blocks: blocks)
  let service = RecordExportService()

  let markdown = try service.markdown(record: record, document: document)
  let markdownImport = try service.importMarkdown(markdown)
  #expect(markdownImport.record == record)
  #expect(markdownImport.document == document)

  let html = try service.html(record: record, document: document)
  let htmlImport = try service.importHTML(html)
  #expect(htmlImport.record == record)
  #expect(htmlImport.document == document)
}

@Test
func packageArchivesReferencedAssetsAndRejectsMissingOrDamagedOriginals() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-export-assets-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("photo.txt")
  try Data("asset-data".utf8).write(to: source)
  let assetStore = try AssetStore(rootURL: root.appendingPathComponent("assets"))
  let asset = try await assetStore.importFile(at: source)
  let recordID = UUID()
  let document = try BlockDocument(recordID: recordID, blocks: [
    Block(
      id: UUID(), recordID: recordID, position: 0, text: "",
      type: .file, content: .assets([AssetPlacement(assetID: asset.id)]))
  ])
  let record = Record(id: recordID, title: "附件")
  let service = RecordExportService(assetStore: assetStore)
  #expect(throws: ExportError.missingAsset(asset.id)) {
    try service.exportPackage(record: record, document: document, to: root.appendingPathComponent("missing.synora"))
  }
  let packageURL = root.appendingPathComponent("record.synora")
  _ = try service.exportPackage(record: record, document: document, assets: [asset], to: packageURL)
  let imported = try service.importPackage(from: packageURL)
  #expect(imported.assets == [asset])
  #expect(imported.assetFiles["assets/\(asset.contentHash)"] == Data("asset-data".utf8))
  try Data("damaged".utf8).write(to: packageURL.appendingPathComponent("assets/\(asset.contentHash)"))
  #expect(throws: ExportError.checksumMismatch("assets/\(asset.contentHash)")) {
    try service.importPackage(from: packageURL)
  }
}
