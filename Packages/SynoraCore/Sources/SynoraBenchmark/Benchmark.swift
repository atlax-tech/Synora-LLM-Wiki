import CryptoKit
import Foundation

public enum BenchmarkProfile: String, Codable, Sendable {
  case smoke
  case full

  public var recordCount: Int {
    self == .full ? 10_000 : 10
  }

  public var blockCount: Int {
    self == .full ? 100_000 : 100
  }

  public var assetBytes: Int64 {
    self == .full ? 20 * 1024 * 1024 * 1024 : 1024 * 1024
  }
}

public struct BenchmarkManifest: Codable, Hashable, Sendable {
  public let schemaVersion: Int
  public let profile: BenchmarkProfile
  public let seed: UInt64
  public let records: Int
  public let blocks: Int
  public let logicalAssetBytes: Int64
  public let physicalBytes: Int64
  public let files: [String: String]

  public init(
    profile: BenchmarkProfile,
    seed: UInt64,
    records: Int,
    blocks: Int,
    logicalAssetBytes: Int64,
    physicalBytes: Int64,
    files: [String: String]
  ) {
    schemaVersion = 1
    self.profile = profile
    self.seed = seed
    self.records = records
    self.blocks = blocks
    self.logicalAssetBytes = logicalAssetBytes
    self.physicalBytes = physicalBytes
    self.files = files
  }
}

public enum BenchmarkError: Error, CustomStringConvertible, Sendable {
  case invalidOutput
  case mismatch(String)

  public var description: String {
    switch self {
    case .invalidOutput: "output must be a directory"
    case .mismatch(let message): message
    }
  }
}

public struct BenchmarkGenerator: Sendable {
  public static let defaultSeed: UInt64 = 2_026_090_5
  private static let chunkSize = 8 * 1024 * 1024

  public init() {}

  public func generate(
    profile: BenchmarkProfile,
    seed: UInt64 = BenchmarkGenerator.defaultSeed,
    output: URL,
    resume: Bool = false
  ) throws -> BenchmarkManifest {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let manifestURL = output.appendingPathComponent("manifest.json")
    if resume, FileManager.default.fileExists(atPath: manifestURL.path) {
      let existing = try JSONDecoder().decode(
        BenchmarkManifest.self, from: Data(contentsOf: manifestURL))
      guard existing.profile == profile, existing.seed == seed else {
        throw BenchmarkError.mismatch("existing manifest profile or seed differs")
      }
      try verify(existing, in: output)
      return existing
    }

    let recordsURL = output.appendingPathComponent("records.jsonl")
    let blocksURL = output.appendingPathComponent("blocks.jsonl")
    let assetURL = output.appendingPathComponent("assets/payload.tiff")
    try FileManager.default.createDirectory(
      at: assetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try writeJSONLines(to: recordsURL, count: profile.recordCount, seed: seed, prefix: "record")
    try writeJSONLines(to: blocksURL, count: profile.blockCount, seed: seed, prefix: "block")
    try writeAsset(to: assetURL, byteCount: profile.assetBytes, seed: seed)

    let files = [
      "records.jsonl": try sha256(recordsURL),
      "blocks.jsonl": try sha256(blocksURL),
      "assets/payload.tiff": try sha256(assetURL),
    ]
    let physicalBytes = try [recordsURL, blocksURL, assetURL].reduce(Int64(0)) {
      $0
        + Int64(
          (try FileManager.default.attributesOfItem(atPath: $1.path)[.size] as? NSNumber)?
            .int64Value ?? 0)
    }
    let manifest = BenchmarkManifest(
      profile: profile,
      seed: seed,
      records: profile.recordCount,
      blocks: profile.blockCount,
      logicalAssetBytes: profile.assetBytes,
      physicalBytes: physicalBytes,
      files: files
    )
    let data = try JSONEncoder().encode(manifest)
    try atomicWrite(data, to: manifestURL)
    return manifest
  }

  public func verify(_ manifest: BenchmarkManifest, in output: URL) throws {
    guard manifest.records == manifest.profile.recordCount,
      manifest.blocks == manifest.profile.blockCount,
      manifest.logicalAssetBytes == manifest.profile.assetBytes
    else { throw BenchmarkError.mismatch("manifest counts do not match profile") }
    for (path, expectedHash) in manifest.files {
      let file = output.appendingPathComponent(path)
      guard FileManager.default.fileExists(atPath: file.path) else {
        throw BenchmarkError.mismatch("missing benchmark file: \(path)")
      }
      guard try sha256(file) == expectedHash else {
        throw BenchmarkError.mismatch("checksum mismatch: \(path)")
      }
    }
  }

  private func writeJSONLines(to url: URL, count: Int, seed: UInt64, prefix: String) throws {
    let temporary = url.appendingPathExtension("tmp")
    try? FileManager.default.removeItem(at: temporary)
    FileManager.default.createFile(atPath: temporary.path, contents: nil)
    let handle = try FileHandle(forWritingTo: temporary)
    defer { try? handle.close() }
    let samples = [
      "中文输入与知识整理",
      "English paragraph with a date 2026-09-05",
      "emoji 🙂 and a developer 👩‍💻",
      "combining e\u{301} and a list item",
      "引用、代码 `let value = 1` 与附件 reference",
    ]
    for index in 0..<count {
      let object: [String: Any] = [
        "id": "\(prefix)-\(index)",
        "seed": NSNumber(value: seed),
        "text": "\(prefix) \(samples[index % samples.count])",
      ]
      let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
      try handle.write(contentsOf: data)
      try handle.write(contentsOf: Data([0x0A]))
    }
    try replaceItem(temporary, at: url)
  }

  private func writeAsset(to url: URL, byteCount: Int64, seed: UInt64) throws {
    let temporary = url.appendingPathExtension("tmp")
    try? FileManager.default.removeItem(at: temporary)
    FileManager.default.createFile(atPath: temporary.path, contents: nil)
    let handle = try FileHandle(forWritingTo: temporary)
    defer { try? handle.close() }
    var remaining = byteCount
    var state = seed
    while remaining > 0 {
      let size = Int(min(Int64(Self.chunkSize), remaining))
      var chunk = Data(count: size)
      chunk.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
        for index in 0..<size {
          state = state &* 6_364_136_223_846_793_005 &+ 1
          bytes[index] = UInt8(truncatingIfNeeded: state >> 56)
        }
      }
      if remaining == byteCount {
        let header = makeTIFFHeader()
        chunk.replaceSubrange(0..<header.count, with: header)
      }
      try handle.write(contentsOf: chunk)
      remaining -= Int64(size)
    }
    try replaceItem(temporary, at: url)
  }

  private func makeTIFFHeader() -> Data {
    var bytes = [UInt8]()
    bytes += [0x49, 0x49, 0x2A, 0x00]
    appendUInt32(8, to: &bytes)
    appendUInt16(10, to: &bytes)
    appendEntry(tag: 256, type: 4, value: 1, to: &bytes)
    appendEntry(tag: 257, type: 4, value: 1, to: &bytes)
    appendEntry(tag: 258, type: 3, value: 8, to: &bytes)
    appendEntry(tag: 259, type: 3, value: 1, to: &bytes)
    appendEntry(tag: 262, type: 3, value: 1, to: &bytes)
    appendEntry(tag: 273, type: 4, value: 134, to: &bytes)
    appendEntry(tag: 277, type: 3, value: 1, to: &bytes)
    appendEntry(tag: 278, type: 4, value: 1, to: &bytes)
    appendEntry(tag: 279, type: 4, value: 1, to: &bytes)
    appendEntry(tag: 284, type: 3, value: 1, to: &bytes)
    appendUInt32(0, to: &bytes)
    precondition(bytes.count == 134)
    return Data(bytes)
  }

  private func appendEntry(tag: UInt16, type: UInt16, value: UInt32, to bytes: inout [UInt8]) {
    appendUInt16(tag, to: &bytes)
    appendUInt16(type, to: &bytes)
    appendUInt32(1, to: &bytes)
    appendUInt32(value, to: &bytes)
  }

  private func appendUInt16(_ value: UInt16, to bytes: inout [UInt8]) {
    bytes += [UInt8(value & 0xFF), UInt8(value >> 8)]
  }

  private func appendUInt32(_ value: UInt32, to bytes: inout [UInt8]) {
    bytes += [
      UInt8(value & 0xFF),
      UInt8((value >> 8) & 0xFF),
      UInt8((value >> 16) & 0xFF),
      UInt8((value >> 24) & 0xFF),
    ]
  }

  private func replaceItem(_ temporary: URL, at destination: URL) throws {
    if FileManager.default.fileExists(atPath: destination.path) {
      _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
    } else {
      try FileManager.default.moveItem(at: temporary, to: destination)
    }
  }

  private func atomicWrite(_ data: Data, to url: URL) throws {
    let temporary = url.appendingPathExtension("tmp")
    try data.write(to: temporary, options: .atomic)
    try? FileManager.default.removeItem(at: url)
    try FileManager.default.moveItem(at: temporary, to: url)
  }

  private func sha256(_ url: URL) throws -> String {
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
