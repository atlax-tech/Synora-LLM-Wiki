import CryptoKit
import Foundation
import SynoraAssets
import SynoraDomain

#if canImport(AppKit)
import AppKit
#endif

public enum ExportError: Error, Equatable, Sendable {
  case destinationExists
  case invalidManifest
  case checksumMismatch(String)
  case pathTraversal
  case idConflict(UUID)
  case invalidDocument
  case unsupportedPDF
}

public struct ArchiveManifest: Codable, Hashable, Sendable {
  public let schemaVersion: Int
  public let recordID: UUID
  public let files: [String]

  public init(schemaVersion: Int = 1, recordID: UUID, files: [String]) {
    self.schemaVersion = schemaVersion
    self.recordID = recordID
    self.files = files
  }
}

public struct ImportedRecord: Sendable {
  public let record: Record
  public let document: BlockDocument
  public let assetFiles: [String: Data]

  public init(record: Record, document: BlockDocument, assetFiles: [String: Data] = [:]) {
    self.record = record
    self.document = document
    self.assetFiles = assetFiles
  }
}

public final class RecordExportService: @unchecked Sendable {
  private let assetStore: AssetStore?

  public init(assetStore: AssetStore? = nil) { self.assetStore = assetStore }

  public func markdown(record: Record, document: BlockDocument) throws -> String {
    guard record.id == document.recordID else { throw ExportError.invalidDocument }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    let metadata = try encoder.encode(record.metadata)
    let metadataText = String(decoding: metadata, as: UTF8.self)
    var output = "---\nrecordID: \(record.id.uuidString)\nkind: \(record.kind.rawValue)\nmetadata: \(metadataText)\n---\n\n# \(escapeMarkdown(record.title))\n\n"
    for block in linearized(document) {
      let parent = block.parentID?.uuidString ?? ""
      output += "<!-- synora:block id=\(block.id.uuidString) type=\(block.type.wireValueForExport) parent=\(parent) order=\(block.orderKey) -->\n"
      output += block.text + "\n\n"
    }
    return output
  }

  public func html(record: Record, document: BlockDocument) throws -> String {
    guard record.id == document.recordID else { throw ExportError.invalidDocument }
    let body = linearized(document).map { block -> String in
      let text = escapeHTML(block.text).replacingOccurrences(of: "\n", with: "<br>")
      switch block.type {
      case .heading1: return "<h1>\(text)</h1>"
      case .heading2: return "<h2>\(text)</h2>"
      case .heading3: return "<h3>\(text)</h3>"
      case .quote: return "<blockquote>\(text)</blockquote>"
      case .code: return "<pre><code>\(text)</code></pre>"
      case .divider: return "<hr>"
      case .bulletedList: return "<ul><li>\(text)</li></ul>"
      case .numberedList: return "<ol><li>\(text)</li></ol>"
      case .task: return "<p>☐ \(text)</p>"
      default: return "<p>\(text)</p>"
      }
    }.joined(separator: "\n")
    return "<!doctype html><html><head><meta charset=\"utf-8\"><title>\(escapeHTML(record.title))</title></head><body><h1>\(escapeHTML(record.title))</h1>\(body)</body></html>"
  }

  @discardableResult
  public func exportPackage(
    record: Record,
    document: BlockDocument,
    assets: [Asset] = [],
    to destinationURL: URL
  ) throws -> URL {
    guard record.id == document.recordID else { throw ExportError.invalidDocument }
    guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
      throw ExportError.destinationExists
    }
    let staging = destinationURL.deletingLastPathComponent()
      .appendingPathComponent(".\(destinationURL.lastPathComponent).staging-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: staging) }
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let recordsURL = staging.appendingPathComponent("records/\(record.id.uuidString)")
    try FileManager.default.createDirectory(at: recordsURL, withIntermediateDirectories: true)
    try encode(record).write(to: recordsURL.appendingPathComponent("record.json"), options: .atomic)
    try encode(document).write(to: recordsURL.appendingPathComponent("document.json"), options: .atomic)
    try markdown(record: record, document: document).data(using: .utf8)!.write(
      to: recordsURL.appendingPathComponent("content.md"), options: .atomic)

    var files = [
      "records/\(record.id.uuidString)/content.md",
      "records/\(record.id.uuidString)/document.json",
      "records/\(record.id.uuidString)/record.json",
    ]
    for asset in assets {
      guard let assetStore else { continue }
      let source = assetStore.fileURL(for: asset)
      guard FileManager.default.fileExists(atPath: source.path) else { continue }
      let relative = "assets/\(asset.contentHash)"
      let target = staging.appendingPathComponent(relative)
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: source, to: target)
      files.append(relative)
    }
    let manifest = ArchiveManifest(recordID: record.id, files: files.sorted())
    try encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
    files.append("manifest.json")
    let checksums = files.sorted().map { path in
      "\(hash(file: staging.appendingPathComponent(path)))  \(path)"
    }.joined(separator: "\n") + "\n"
    try checksums.data(using: .utf8)!.write(
      to: staging.appendingPathComponent("checksums.sha256"), options: .atomic)
    try FileManager.default.moveItem(at: staging, to: destinationURL)
    return destinationURL
  }

  public func importPackage(
    from packageURL: URL,
    existingRecordIDs: Set<UUID> = []
  ) throws -> ImportedRecord {
    let manifestURL = packageURL.appendingPathComponent("manifest.json")
    let manifest = try decode(ArchiveManifest.self, at: manifestURL)
    guard manifest.schemaVersion == 1, !existingRecordIDs.contains(manifest.recordID) else {
      if existingRecordIDs.contains(manifest.recordID) { throw ExportError.idConflict(manifest.recordID) }
      throw ExportError.invalidManifest
    }
    let checksums = try String(contentsOf: packageURL.appendingPathComponent("checksums.sha256"), encoding: .utf8)
    for line in checksums.split(separator: "\n") {
      let value = String(line)
      guard let separator = value.range(of: "  ") else { throw ExportError.invalidManifest }
      let expectedHash = String(value[..<separator.lowerBound])
      let relativePath = String(value[separator.upperBound...])
      let path = try safePath(relativePath, under: packageURL)
      guard hash(file: path) == expectedHash else { throw ExportError.checksumMismatch(relativePath) }
    }
    for path in manifest.files { _ = try safePath(path, under: packageURL) }
    let record = try decode(Record.self, at: packageURL.appendingPathComponent("records/\(manifest.recordID.uuidString)/record.json"))
    let document = try decode(BlockDocument.self, at: packageURL.appendingPathComponent("records/\(manifest.recordID.uuidString)/document.json"))
    guard record.id == manifest.recordID, document.recordID == record.id else { throw ExportError.invalidDocument }
    var assetFiles: [String: Data] = [:]
    for path in manifest.files where path.hasPrefix("assets/") {
      assetFiles[path] = try Data(contentsOf: safePath(path, under: packageURL))
    }
    return ImportedRecord(record: record, document: document, assetFiles: assetFiles)
  }

  public func importMarkdown(_ markdown: String, recordID: UUID = UUID(), kind: RecordKind = .note) throws -> ImportedRecord {
    let lines = markdown.components(separatedBy: .newlines)
    let title = lines.first(where: { $0.hasPrefix("# ") })?.dropFirst(2).trimmingCharacters(in: .whitespaces) ?? "Untitled"
    let body = lines.filter { !$0.hasPrefix("---") && !$0.hasPrefix("# ") && !$0.hasPrefix("<!--") && !$0.isEmpty }.joined(separator: "\n")
    let record = Record(id: recordID, title: title, kind: kind)
    let block = Block(id: UUID(), recordID: recordID, position: 0, text: body)
    return ImportedRecord(record: record, document: try BlockDocument(recordID: recordID, blocks: [block]))
  }

  #if canImport(AppKit)
  @MainActor public func exportPDF(record: Record, document: BlockDocument, to destinationURL: URL) throws {
    guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
      throw ExportError.destinationExists
    }
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 10_000))
    view.string = try markdown(record: record, document: document)
    view.isEditable = false
    let data = view.dataWithPDF(inside: view.bounds)
    try data.write(to: destinationURL, options: .atomic)
  }
  #else
  public func exportPDF(record: Record, document: BlockDocument, to destinationURL: URL) throws {
    throw ExportError.unsupportedPDF
  }
  #endif

  private func linearized(_ document: BlockDocument) -> [Block] {
    func visit(_ parentID: UUID?) -> [Block] {
      document.children(of: parentID).flatMap { [$0] + visit($0.id) }
    }
    return visit(nil)
  }

  private func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
  }

  private func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
    try JSONDecoder.withSecondsSince1970.decode(type, from: Data(contentsOf: url))
  }

  private func hash(file url: URL) -> String {
    guard let data = try? Data(contentsOf: url) else { return "" }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func safePath(_ path: String, under root: URL) throws -> URL {
    let candidate = root.appendingPathComponent(path).standardizedFileURL
    guard candidate.path == root.standardizedFileURL.path || candidate.path.hasPrefix(root.standardizedFileURL.path + "/") else {
      throw ExportError.pathTraversal
    }
    return candidate
  }

  private func escapeMarkdown(_ value: String) -> String { value.replacingOccurrences(of: "\n", with: " ") }
  private func escapeHTML(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}

private extension JSONDecoder {
  static var withSecondsSince1970: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return decoder
  }
}

private extension BlockType {
  var wireValueForExport: String {
    switch self {
    case .bulletedList: "bulleted-list"
    case .numberedList: "numbered-list"
    default: String(describing: self)
    }
  }
}
