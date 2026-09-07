import Foundation
import Testing

@testable import SynoraExport
import SynoraDomain

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
