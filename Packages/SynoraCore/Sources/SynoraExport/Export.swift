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
  case missingAsset(UUID)
  case invalidDocument
  case invalidHTML
  case unsupportedPDF
}

public struct ArchiveManifest: Codable, Hashable, Sendable {
  public let schemaVersion: Int
  public let recordID: UUID
  public let files: [String]
  public let assets: [Asset]

  public init(schemaVersion: Int = 1, recordID: UUID, files: [String], assets: [Asset] = []) {
    self.schemaVersion = schemaVersion
    self.recordID = recordID
    self.files = files
    self.assets = assets
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, recordID, files, assets
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    recordID = try container.decode(UUID.self, forKey: .recordID)
    files = try container.decode([String].self, forKey: .files)
    assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
  }
}

public struct ImportedRecord: Sendable {
  public let record: Record
  public let document: BlockDocument
  public let assetFiles: [String: Data]
  public let assets: [Asset]

  public init(
    record: Record,
    document: BlockDocument,
    assetFiles: [String: Data] = [:],
    assets: [Asset] = []
  ) {
    self.record = record
    self.document = document
    self.assetFiles = assetFiles
    self.assets = assets
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
    let recordToken = try token(for: record)
    var output = "---\nschemaVersion: 1\nrecordID: \(record.id.uuidString)\nkind: \(record.kind.rawValue)\nmetadata: \(metadataText)\nrecord: \(recordToken)\n---\n\n# \(escapeMarkdown(record.title))\n\n"
    for block in linearized(document) {
      let parent = block.parentID?.uuidString ?? ""
      output += "<!-- synora:block id=\(block.id.uuidString) type=\(block.type.wireValueForExport) parent=\(parent) order=\(block.orderKey) payload=\(try token(for: block)) -->\n"
      output += block.text + "\n\n"
    }
    return output
  }

  public func html(record: Record, document: BlockDocument) throws -> String {
    guard record.id == document.recordID else { throw ExportError.invalidDocument }
    let recordToken = try token(for: record)
    let body = linearized(document).map { block -> String in
      let text = escapeHTML(block.text).replacingOccurrences(of: "\n", with: "<br>")
      let payload = (try? token(for: block)) ?? ""
      let marker = " data-synora-block-id=\"\(block.id.uuidString)\" data-synora-block=\"\(payload)\""
      switch block.type {
      case .heading1: return "<h1\(marker)>\(text)</h1>"
      case .heading2: return "<h2\(marker)>\(text)</h2>"
      case .heading3: return "<h3\(marker)>\(text)</h3>"
      case .quote: return "<blockquote\(marker)>\(text)</blockquote>"
      case .code: return "<pre\(marker)><code>\(text)</code></pre>"
      case .divider: return "<hr\(marker)>"
      case .bulletedList: return "<ul\(marker)><li>\(text)</li></ul>"
      case .numberedList: return "<ol\(marker)><li>\(text)</li></ol>"
      case .task: return "<p\(marker)>☐ \(text)</p>"
      default: return "<p\(marker)>\(text)</p>"
      }
    }.joined(separator: "\n")
    return "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"synora-record\" content=\"\(recordToken)\"><title>\(escapeHTML(record.title))</title></head><body><h1>\(escapeHTML(record.title))</h1>\(body)</body></html>"
  }

  @discardableResult
  public func exportPackage(
    record: Record,
    document: BlockDocument,
    assets: [Asset] = [],
    to destinationURL: URL
  ) throws -> URL {
    guard record.id == document.recordID else { throw ExportError.invalidDocument }
    try document.validate()
    guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
      throw ExportError.destinationExists
    }
    let referencedIDs = Set(document.blocks.flatMap { block -> [UUID] in
      guard case .assets(let placements)? = block.content else { return [] }
      return placements.map(\.assetID)
    })
    guard Set(assets.map(\.id)).count == assets.count else { throw ExportError.invalidManifest }
    let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
    let archivedAssets = try referencedIDs.sorted { $0.uuidString < $1.uuidString }.map { id -> Asset in
      guard let asset = assetsByID[id], let assetStore else { throw ExportError.missingAsset(id) }
      guard isValidHash(asset.contentHash) else { throw ExportError.invalidManifest }
      let source = assetStore.fileURL(for: asset)
      guard FileManager.default.fileExists(atPath: source.path) else {
        throw ExportError.missingAsset(id)
      }
      guard hash(file: source) == asset.contentHash else {
        throw ExportError.checksumMismatch("assets/\(asset.contentHash)")
      }
      return asset
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
    if let assetStore {
      for asset in archivedAssets {
        let source = assetStore.fileURL(for: asset)
        let relative = "assets/\(asset.contentHash)"
        let target = staging.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: target.path) {
          try FileManager.default.copyItem(at: source, to: target)
        }
        files.append(relative)
      }
    }
    let manifest = ArchiveManifest(recordID: record.id, files: files.sorted(), assets: archivedAssets)
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
    guard manifest.schemaVersion == 1,
      Set(manifest.files).count == manifest.files.count,
      !existingRecordIDs.contains(manifest.recordID)
    else {
      if existingRecordIDs.contains(manifest.recordID) { throw ExportError.idConflict(manifest.recordID) }
      throw ExportError.invalidManifest
    }
    let checksums = try String(contentsOf: packageURL.appendingPathComponent("checksums.sha256"), encoding: .utf8)
    var checksumPaths = Set<String>()
    for line in checksums.split(separator: "\n") {
      let value = String(line)
      guard let separator = value.range(of: "  ") else { throw ExportError.invalidManifest }
      let expectedHash = String(value[..<separator.lowerBound])
      let relativePath = String(value[separator.upperBound...])
      guard checksumPaths.insert(relativePath).inserted else { throw ExportError.invalidManifest }
      let path = try safePath(relativePath, under: packageURL)
      guard hash(file: path) == expectedHash else { throw ExportError.checksumMismatch(relativePath) }
    }
    guard checksumPaths == Set(manifest.files).union(["manifest.json"]) else {
      throw ExportError.invalidManifest
    }
    for path in manifest.files { _ = try safePath(path, under: packageURL) }
    let recordPath = "records/\(manifest.recordID.uuidString)/record.json"
    let documentPath = "records/\(manifest.recordID.uuidString)/document.json"
    guard manifest.files.contains(recordPath), manifest.files.contains(documentPath) else {
      throw ExportError.invalidManifest
    }
    let record = try decode(Record.self, at: packageURL.appendingPathComponent("records/\(manifest.recordID.uuidString)/record.json"))
    let document = try decode(BlockDocument.self, at: packageURL.appendingPathComponent("records/\(manifest.recordID.uuidString)/document.json"))
    guard record.id == manifest.recordID, document.recordID == record.id else { throw ExportError.invalidDocument }
    try document.validate()
    var assetFiles: [String: Data] = [:]
    let assetsByPath = Dictionary(uniqueKeysWithValues: manifest.assets.map {
      ("assets/\($0.contentHash)", $0)
    })
    for path in manifest.files where path.hasPrefix("assets/") {
      guard let asset = assetsByPath[path], path == "assets/\(asset.contentHash)" else {
        throw ExportError.invalidManifest
      }
      let data = try Data(contentsOf: safePath(path, under: packageURL))
      guard Int64(data.count) == asset.byteCount, hash(data: data) == asset.contentHash else {
        throw ExportError.checksumMismatch(path)
      }
      assetFiles[path] = data
    }
    for asset in manifest.assets {
      let path = "assets/\(asset.contentHash)"
      guard manifest.files.contains(path), assetFiles[path] != nil else {
        throw ExportError.missingAsset(asset.id)
      }
    }
    let referencedIDs = Set(document.blocks.flatMap { block -> [UUID] in
      guard case .assets(let placements)? = block.content else { return [] }
      return placements.map(\.assetID)
    })
    for id in referencedIDs {
      guard let asset = manifest.assets.first(where: { $0.id == id }),
        assetFiles["assets/\(asset.contentHash)"] != nil
      else { throw ExportError.missingAsset(id) }
    }
    return ImportedRecord(record: record, document: document, assetFiles: assetFiles, assets: manifest.assets)
  }

  public func importMarkdown(_ markdown: String, recordID: UUID = UUID(), kind: RecordKind = .note) throws -> ImportedRecord {
    let lines = markdown.components(separatedBy: .newlines)
    var frontmatter: [String: String] = [:]
    if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
      for line in lines[1..<end] {
        guard let separator = line.firstIndex(of: ":") else { continue }
        let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        frontmatter[key] = value
      }
    }
    let heading = lines.first(where: { $0.hasPrefix("# ") })
      .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
    var importedRecord = frontmatter["record"].flatMap { decodeToken(Record.self, from: $0) }
      ?? Record(
        id: UUID(uuidString: frontmatter["recordID"] ?? "") ?? recordID,
        title: heading ?? "Untitled",
        kind: RecordKind(rawValue: frontmatter["kind"] ?? "") ?? kind)
    if let heading { importedRecord.title = heading }
    if let value = frontmatter["kind"], let parsedKind = RecordKind(rawValue: value) {
      importedRecord.kind = parsedKind
    }
    if let metadata = frontmatter["metadata"], let parsed = try? JSONDecoder().decode([String: String].self, from: Data(metadata.utf8))
    {
      importedRecord.metadata = parsed
    }

    var blocks: [Block] = []
    for line in lines where line.hasPrefix("<!-- synora:block ") {
      let values = markerValues(from: line)
      if let payload = values["payload"], let decoded = decodeToken(Block.self, from: payload) {
        blocks.append(copying(decoded, recordID: importedRecord.id))
      } else if let id = values["id"].flatMap(UUID.init(uuidString:)),
        let type = values["type"].flatMap(blockType(from:)),
        let order = values["order"].flatMap(Int64.init)
      {
        let parent = values["parent"].flatMap(UUID.init(uuidString:))
        let index = blocks.count
        let body = visibleMarkdownBody(after: line, in: lines)
        blocks.append(Block(
          id: id,
          recordID: importedRecord.id,
          position: index,
          text: body,
          parentID: parent,
          type: type,
          orderKey: order))
      }
    }
    if blocks.isEmpty {
      let body = lines.filter {
        !$0.hasPrefix("---") && !$0.hasPrefix("# ") && !$0.hasPrefix("<!--") && !$0.isEmpty
      }.joined(separator: "\n")
      if !body.isEmpty {
        blocks = [Block(id: UUID(), recordID: importedRecord.id, position: 0, text: body)]
      }
    }
    return ImportedRecord(
      record: importedRecord,
      document: try BlockDocument(recordID: importedRecord.id, blocks: blocks))
  }

  public func importHTML(_ html: String, recordID: UUID = UUID(), kind: RecordKind = .note) throws -> ImportedRecord {
    var record = htmlAttribute("content", in: html, forMetaName: "synora-record")
      .flatMap { decodeToken(Record.self, from: $0) }
      ?? Record(id: recordID, title: "Untitled", kind: kind)
    if let title = firstHTMLText(for: "title", in: html) ?? firstHTMLText(for: "h1", in: html) {
      record.title = title
    }
    var blocks: [Block] = []
    for payload in htmlAttributes(named: "data-synora-block", in: html) {
      guard let block = decodeToken(Block.self, from: payload) else { continue }
      blocks.append(copying(block, recordID: record.id))
    }
    if blocks.isEmpty {
      let body = visibleHTMLText(html)
        .replacingOccurrences(of: record.title, with: "", options: .caseInsensitive)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !body.isEmpty {
        blocks = [Block(id: UUID(), recordID: record.id, position: 0, text: body)]
      }
    }
    guard let document = try? BlockDocument(recordID: record.id, blocks: blocks) else {
      throw ExportError.invalidHTML
    }
    return ImportedRecord(record: record, document: document)
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

  private func token<T: Encodable>(for value: T) throws -> String {
    try encode(value).base64EncodedString()
  }

  private func decodeToken<T: Decodable>(_ type: T.Type, from value: String) -> T? {
    guard let data = Data(base64Encoded: value) else { return nil }
    return try? JSONDecoder.withSecondsSince1970.decode(type, from: data)
  }

  private func markerValues(from line: String) -> [String: String] {
    let marker = line
      .replacingOccurrences(of: "<!-- synora:block", with: "")
      .replacingOccurrences(of: "-->", with: "")
    return marker.split(whereSeparator: \.isWhitespace).reduce(into: [:]) { values, part in
      let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
      guard pair.count == 2 else { return }
      values[pair[0]] = pair[1]
    }
  }

  private func blockType(from value: String) -> BlockType? {
    switch value {
    case "paragraph": .paragraph
    case "heading1": .heading1
    case "heading2": .heading2
    case "heading3": .heading3
    case "bulleted-list": .bulletedList
    case "numbered-list": .numberedList
    case "task": .task
    case "quote": .quote
    case "code": .code
    case "divider": .divider
    case "table": .table
    case "toggle": .toggle
    case "callout": .callout
    case "image": .image
    case "gallery": .gallery
    case "video": .video
    case "audio": .audio
    case "pdf": .pdf
    case "file": .file
    case "link": .link
    default: .unknown(value)
    }
  }

  private func copying(_ block: Block, recordID: UUID) -> Block {
    Block(
      id: block.id,
      recordID: recordID,
      position: block.position,
      text: block.text,
      revision: block.revision,
      parentID: block.parentID,
      type: block.type,
      orderKey: block.orderKey,
      inlineAttributes: block.inlineAttributes,
      attributes: block.attributes,
      unknownFields: block.unknownFields,
      content: block.content)
  }

  private func visibleMarkdownBody(after marker: String, in lines: [String]) -> String {
    guard let index = lines.firstIndex(of: marker) else { return "" }
    return lines.dropFirst(index + 1).first(where: { !$0.isEmpty && !$0.hasPrefix("<!--") }) ?? ""
  }

  private func htmlAttributes(named name: String, in html: String) -> [String] {
    let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*[\\\"']([^\\\"']*)[\\\"']"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return []
    }
    let range = NSRange(html.startIndex..<html.endIndex, in: html)
    return regex.matches(in: html, range: range).compactMap { match in
      guard match.numberOfRanges > 1, let valueRange = Range(match.range(at: 1), in: html)
      else { return nil }
      return String(html[valueRange])
    }
  }

  private func htmlAttribute(_ attributeName: String, in html: String, forMetaName metaName: String) -> String? {
    let tagPattern = "<meta\\b[^>]*>"
    guard let regex = try? NSRegularExpression(pattern: tagPattern, options: [.caseInsensitive]) else {
      return nil
    }
    let range = NSRange(html.startIndex..<html.endIndex, in: html)
    for match in regex.matches(in: html, range: range) {
      guard let tagRange = Range(match.range, in: html) else { continue }
      let tag = String(html[tagRange])
      guard attribute(named: "name", in: tag)?.caseInsensitiveCompare(metaName) == .orderedSame else {
        continue
      }
      return attribute(named: attributeName, in: tag)
    }
    return nil
  }

  private func attribute(named name: String, in tag: String) -> String? {
    let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*[\\\"']([^\\\"']*)[\\\"']"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
      let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..<tag.endIndex, in: tag)),
      let valueRange = Range(match.range(at: 1), in: tag)
    else { return nil }
    return String(tag[valueRange])
  }

  private func firstHTMLText(for tag: String, in html: String) -> String? {
    let pattern = "<\(tag)\\b[^>]*>([\\s\\S]*?)</\(tag)>"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
      let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
      let valueRange = Range(match.range(at: 1), in: html)
    else { return nil }
    return visibleHTMLText(String(html[valueRange]))
  }

  private func visibleHTMLText(_ html: String) -> String {
    html
      .replacingOccurrences(of: "(?is)<script[^>]*>.*?</script>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "(?is)<style[^>]*>.*?</style>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
      .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
    try JSONDecoder.withSecondsSince1970.decode(type, from: Data(contentsOf: url))
  }

  private func hash(file url: URL) -> String {
    guard let data = try? Data(contentsOf: url) else { return "" }
    return hash(data: data)
  }

  private func hash(data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func safePath(_ path: String, under root: URL) throws -> URL {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else {
      throw ExportError.pathTraversal
    }
    let candidate = root.appendingPathComponent(path).standardizedFileURL
    guard candidate.path == root.standardizedFileURL.path || candidate.path.hasPrefix(root.standardizedFileURL.path + "/") else {
      throw ExportError.pathTraversal
    }
    return candidate
  }

  private func isValidHash(_ value: String) -> Bool {
    value.count == 64 && value.unicodeScalars.allSatisfy {
      switch $0.value {
      case 48...57, 65...70, 97...102: true
      default: false
      }
    }
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
