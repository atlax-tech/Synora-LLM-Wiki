import Foundation
import SynoraAssets
import SynoraDomain
import SynoraStore

@main
struct SynoraP2Performance {
  private struct Report: Codable {
    let textUTF16Length: Int
    let mediaPlacements: Int
    let decodedImages: Int
    let decodedPDFs: Int
    let decodedAudio: Int
    let editSamples: Int
    let editP95Milliseconds: Double
    let saveMilliseconds: Double
    let reopenMilliseconds: Double
    let persistedRevision: Int
    let modelOnly: Bool
    let ime: String
    let voiceOver: String
    let keystrokeToPaint: String
  }

  static func main() async {
    do {
      try await run()
    } catch {
      fputs("P2 performance failed: \(error)\n", stderr)
      exit(1)
    }
  }

  private static func run() async throws {
    let output = URL(fileURLWithPath: argument(after: "--output") ??
      FileManager.default.temporaryDirectory
        .appendingPathComponent("synora-p2-performance-\(UUID().uuidString)", isDirectory: true)
        .path, isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let sources = output.appendingPathComponent("sources", isDirectory: true)
    try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    let assetStore = try AssetStore(rootURL: output.appendingPathComponent("assets"))
    let fixtureKinds = ["png", "pdf", "wav"]
    var assets: [Asset] = []
    assets.reserveCapacity(200)
    var decoded = (images: 0, pdfs: 0, audio: 0)
    for index in 0..<200 {
      let kind = fixtureKinds[index % fixtureKinds.count]
      let source = sources.appendingPathComponent("media-\(index).\(kind)")
      try fixtureData(kind: kind).write(to: source, options: .atomic)
      let asset = try await assetStore.importFile(at: source)
      assets.append(asset)
      switch assetStore.preview(for: asset).kind {
      case .image: decoded.images += 1
      case .pdf: decoded.pdfs += 1
      case .audio: decoded.audio += 1
      default: break
      }
    }

    let text = String(repeating: "中文输入🙂", count: 25_000)
    let recordID = UUID()
    let textBlocks = try textBlocks(text, recordID: recordID)
    let gallery = Block(
      id: UUID(), recordID: recordID, position: textBlocks.count, text: "",
      type: .gallery,
      content: .assets(assets.enumerated().map { index, asset in
        AssetPlacement(assetID: asset.id, order: index)
      }))
    let document = try BlockDocument(recordID: recordID, blocks: textBlocks + [gallery])
    let record = Record(id: recordID, title: "P2 performance", metadata: ["fixture": "100k+200"])
    let store = try ProductStore(path: output.appendingPathComponent("library.sqlite").path)
    let saveStart = Date()
    var expectedRevision = 0
    var currentRecord = record
    for asset in assets {
      let receipt = try store.save(
        asset: asset,
        record: currentRecord,
        document: document,
        expectedRevision: expectedRevision)
      expectedRevision = receipt.revision
      currentRecord.revision = receipt.revision
    }
    let saveMilliseconds = Date().timeIntervalSince(saveStart) * 1_000

    let reopenStart = Date()
    let reopened = try ProductStore(path: output.appendingPathComponent("library.sqlite").path)
    let reopenedDocument = try reopened.document(recordID: recordID)
    let reopenMilliseconds = Date().timeIntervalSince(reopenStart) * 1_000

    guard let first = reopenedDocument.blocks.first else { throw CocoaError(.fileReadCorruptFile) }
    var samples: [Double] = []
    samples.reserveCapacity(1_000)
    var working = reopenedDocument
    for index in 0..<1_000 {
      let start = Date()
      working = try working.editing(id: first.id, text: first.text + String(index))
      samples.append(Date().timeIntervalSince(start) * 1_000)
    }
    samples.sort()
    let p95Index = min(samples.count - 1, Int(Double(samples.count - 1) * 0.95))
    let report = Report(
      textUTF16Length: (text as NSString).length,
      mediaPlacements: assets.count,
      decodedImages: decoded.images,
      decodedPDFs: decoded.pdfs,
      decodedAudio: decoded.audio,
      editSamples: samples.count,
      editP95Milliseconds: samples[p95Index],
      saveMilliseconds: saveMilliseconds,
      reopenMilliseconds: reopenMilliseconds,
      persistedRevision: try reopened.record(id: recordID)?.revision ?? 0,
      modelOnly: true,
      ime: "UNVERIFIED_REAL_SYSTEM_INPUT",
      voiceOver: "UNVERIFIED_REAL_VOICEOVER",
      keystrokeToPaint: "UNVERIFIED_INSTRUMENTS")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    try encoder.encode(report).write(to: output.appendingPathComponent("report.json"), options: .atomic)
    print("P2_PERFORMANCE_REPORT=\(output.appendingPathComponent("report.json").path)")
  }

  private static func argument(after flag: String) -> String? {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }

  private static func textBlocks(_ text: String, recordID: UUID) throws -> [Block] {
    let value = text as NSString
    var blocks: [Block] = []
    var offset = 0
    while offset < value.length {
      let length = min(1_000, value.length - offset)
      blocks.append(Block(
        id: UUID(), recordID: recordID, position: blocks.count,
        text: value.substring(with: NSRange(location: offset, length: length))))
      offset += length
    }
    return blocks
  }

  private static func fixtureData(kind: String) throws -> Data {
    switch kind {
    case "png":
      return Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    case "pdf":
      return Data(base64Encoded: "JVBERi0xLjQKJeLjz9MKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCAxMCAxMF0gL0NvbnRlbnRzIDQgMCBSID4+CmVuZG9iago0IDAgb2JqCjw8IC9MZW5ndGggMCA+PgpzdHJlYW0KCmVuZHN0cmVhbQplbmRvYmoKeHJlZgowIDUKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDE1IDAwMDAwIG4gCjAwMDAwMDA2NCAwMDAwMCBuIAowMDAwMDAwMTIxIDAwMDAwIG4gCjAwMDAwMDIwNiAwMDAwMCBuIAp0cmFpbGVyCjw8IC9TaXplIDUgL1Jvb3QgMSAwIFIgPj4Kc3RhcnR4cmVmCjI1NQolJUVPRgo=")!
    case "wav":
      var data = Data("RIFF".utf8)
      func appendLE(_ value: UInt32) {
        data.append(contentsOf: [
          UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8),
          UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 24),
        ])
      }
      data.append(contentsOf: [0, 0, 0, 0])
      data.append(contentsOf: Data("WAVEfmt ".utf8))
      appendLE(16)
      data.append(contentsOf: [1, 0, 1, 0])
      appendLE(8_000)
      appendLE(8_000)
      data.append(contentsOf: [1, 0, 8, 0])
      data.append(contentsOf: Data("data".utf8))
      appendLE(8)
      data.append(contentsOf: repeatElement(UInt8(128), count: 8))
      let size = UInt32(data.count - 8)
      data.replaceSubrange(4..<8, with: Data([
        UInt8(truncatingIfNeeded: size), UInt8(truncatingIfNeeded: size >> 8),
        UInt8(truncatingIfNeeded: size >> 16), UInt8(truncatingIfNeeded: size >> 24),
      ]))
      return data
    default:
      throw CocoaError(.fileReadUnknown)
    }
  }
}
