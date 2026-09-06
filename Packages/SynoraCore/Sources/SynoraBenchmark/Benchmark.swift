import CryptoKit
import Foundation

public enum BenchmarkProfile: String, Codable, Sendable {
  case smoke
  case full

  public var recordCount: Int { self == .full ? 10_000 : 10 }
  public var blockCount: Int { self == .full ? 100_000 : 100 }
  public var assetBytes: Int64 { self == .full ? 20 * 1024 * 1024 * 1024 : 1024 * 1024 }
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
  public let media: [String: String]

  public init(
    profile: BenchmarkProfile,
    seed: UInt64,
    records: Int,
    blocks: Int,
    logicalAssetBytes: Int64,
    physicalBytes: Int64,
    files: [String: String],
    media: [String: String] = BenchmarkGenerator.mediaPaths
  ) {
    schemaVersion = 2
    self.profile = profile
    self.seed = seed
    self.records = records
    self.blocks = blocks
    self.logicalAssetBytes = logicalAssetBytes
    self.physicalBytes = physicalBytes
    self.files = files
    self.media = media
  }
}

public enum BenchmarkError: Error, CustomStringConvertible, Equatable, Sendable {
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
  public static let mediaPaths: [String: String] = [
    "image": "assets/preview.png",
    "document": "assets/preview.pdf",
    "audio": "assets/preview.wav",
    "video": "assets/preview.mp4",
  ]

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
    let assetsDirectory = output.appendingPathComponent("assets", isDirectory: true)
    try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
    try writeJSONLines(to: recordsURL, count: profile.recordCount, seed: seed, prefix: "record")
    try writeJSONLines(to: blocksURL, count: profile.blockCount, seed: seed, prefix: "block")

    let media = try writeMediaAssets(to: assetsDirectory)
    let mediaBytes = media.reduce(Int64(0)) { $0 + $1.byteCount }
    guard profile.assetBytes >= mediaBytes else {
      throw BenchmarkError.mismatch("profile asset budget is smaller than media fixtures")
    }
    let payloadURL = assetsDirectory.appendingPathComponent("payload.bin")
    try writePayload(to: payloadURL, byteCount: profile.assetBytes - mediaBytes, seed: seed)

    var files = [
      "records.jsonl": try sha256(recordsURL),
      "blocks.jsonl": try sha256(blocksURL),
    ]
    for fixture in media {
      files[fixture.path] = try sha256(fixture.url)
    }
    files["assets/payload.bin"] = try sha256(payloadURL)

    let allURLs = [recordsURL, blocksURL] + media.map(\.url) + [payloadURL]
    let physicalBytes = try allURLs.reduce(Int64(0)) { total, url in
      let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
      return total + (size?.int64Value ?? 0)
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
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    try atomicWrite(encoder.encode(manifest), to: manifestURL)
    return manifest
  }

  public func verify(_ manifest: BenchmarkManifest, in output: URL) throws {
    guard manifest.schemaVersion == 2 else {
      throw BenchmarkError.mismatch("unsupported benchmark manifest schema")
    }
    guard manifest.records == manifest.profile.recordCount,
      manifest.blocks == manifest.profile.blockCount,
      manifest.logicalAssetBytes == manifest.profile.assetBytes
    else { throw BenchmarkError.mismatch("manifest counts do not match profile") }

    let expectedPaths: Set<String> = [
      "records.jsonl", "blocks.jsonl", "assets/payload.bin", "assets/preview.png",
      "assets/preview.pdf", "assets/preview.wav", "assets/preview.mp4",
    ]
    guard Set(manifest.files.keys) == expectedPaths else {
      throw BenchmarkError.mismatch("manifest file set does not match profile")
    }
    guard manifest.media == Self.mediaPaths else {
      throw BenchmarkError.mismatch("manifest media map does not match profile")
    }

    var physicalBytes: Int64 = 0
    var logicalAssetBytes: Int64 = 0
    for (path, expectedHash) in manifest.files {
      let file = output.appendingPathComponent(path)
      guard FileManager.default.fileExists(atPath: file.path) else {
        throw BenchmarkError.mismatch("missing benchmark file: \(path)")
      }
      guard try sha256(file) == expectedHash else {
        throw BenchmarkError.mismatch("checksum mismatch: \(path)")
      }
      guard
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber
      else { throw BenchmarkError.mismatch("missing file size: \(path)") }
      physicalBytes += size.int64Value
      if path.hasPrefix("assets/") { logicalAssetBytes += size.int64Value }
    }
    guard logicalAssetBytes == manifest.logicalAssetBytes else {
      throw BenchmarkError.mismatch("manifest logical asset bytes do not match files")
    }
    guard physicalBytes == manifest.physicalBytes else {
      throw BenchmarkError.mismatch("manifest physical bytes do not match files")
    }
  }

  private struct MediaFile {
    let path: String
    let url: URL
    let byteCount: Int64
  }

  private func writeMediaAssets(to directory: URL) throws -> [MediaFile] {
    let fixtures: [(String, Data)] = [
      ("preview.png", Self.pngFixture),
      ("preview.pdf", Self.pdfFixture),
      ("preview.wav", Self.wavFixture),
      ("preview.mp4", Self.mp4Fixture),
    ]
    return try fixtures.map { name, data in
      let url = directory.appendingPathComponent(name)
      try data.write(to: url, options: .atomic)
      return MediaFile(path: "assets/\(name)", url: url, byteCount: Int64(data.count))
    }
  }

  private func writePayload(to url: URL, byteCount: Int64, seed: UInt64) throws {
    try writeAsset(to: url, byteCount: byteCount, seed: seed)
  }

  private static let pngFixture = Data(
    base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
  )!

  private static let pdfFixture = Data(
    base64Encoded:
      "JVBERi0xLjQKJeLjz9MKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCAxMCAxMF0gL0NvbnRlbnRzIDQgMCBSID4+CmVuZG9iago0IDAgb2JqCjw8IC9MZW5ndGggMCA+PgpzdHJlYW0KCmVuZHN0cmVhbQplbmRvYmoKeHJlZgowIDUKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDE1IDAwMDAwIG4gCjAwMDAwMDA2NCAwMDAwMCBuIAowMDAwMDAwMTIxIDAwMDAwIG4gCjAwMDAwMDIwNiAwMDAwMCBuIAp0cmFpbGVyCjw8IC9TaXplIDUgL1Jvb3QgMSAwIFIgPj4Kc3RhcnR4cmVmCjI1NQolJUVPRgo="
  )!

  private static let wavFixture: Data = {
    var data = Data("RIFF".utf8)
    func appendLE(_ value: UInt32) {
      data.append(UInt8(truncatingIfNeeded: value))
      data.append(UInt8(truncatingIfNeeded: value >> 8))
      data.append(UInt8(truncatingIfNeeded: value >> 16))
      data.append(UInt8(truncatingIfNeeded: value >> 24))
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
    let riffSize = UInt32(data.count - 8)
    data.replaceSubrange(
      4..<8,
      with: Data([
        UInt8(truncatingIfNeeded: riffSize),
        UInt8(truncatingIfNeeded: riffSize >> 8),
        UInt8(truncatingIfNeeded: riffSize >> 16),
        UInt8(truncatingIfNeeded: riffSize >> 24),
      ]))
    return data
  }()

  private static let mp4Fixture = Data(
    base64Encoded:
      "AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAMVbW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAAAAAD6AAAA+gAAQAAAQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAA"
      + "AAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAj90cmFrAAAAXHRraGQAAAADAAAAAAAAAAAAAAABAAAAAAAAA+gAAAAA"
      + "AAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAABAAAAAQAAAAAAAkZWR0cwAAABxlbHN0AAAAAAAAAAEAAAPoAAAAAAABAAAAAAG3"
      + "bWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAABAAAAAQABVxAAAAAAALWhkbHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAABYm1pbmYAAAAUdm1o"
      + "ZAAAAAEAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAAAQAAASJzdGJsAAAAvnN0c2QAAAAAAAAAAQAAAK5hdmMxAAAAAAAAAAEAAAAAAAAA"
      + "AAAAAAAAAAAAABAAEABIAAAASAAAAAAAAAABFUxhdmM2Mi4yOC4xMDEgbGlieDI2NAAAAAAAAAAAAAAAGP//AAAANGF2Y0MBZAAK/+EAF2dkAAqs2V7ARAAAAwAEAAAD"
      + "AAg8SJZYAQAGaOvjyyLA/fj4AAAAABBwYXNwAAAAAQAAAAEAAAAUYnRydAAAAAAAABYoAAAAAAAAABhzdHRzAAAAAAAAAAEAAAABAABAAAAAABxzdHNjAAAAAAAAAAEA"
      + "AAABAAAAAQAAAAEAAAAUc3RzegAAAAAAAALFAAAAAQAAABRzdGNvAAAAAAAAAAEAAANFAAAAYnVkdGEAAABabWV0YQAAAAAAAAAhaGRscgAAAAAAAAAAbWRpcmFwcGwA"
      + "AAAAAAAAAAAAAAAtaWxzdAAAACWpdG9vAAAAHWRhdGEAAAABAAAAAExhdmY2Mi4xMi4xMDEAAAAIZnJlZQAAAs1tZGF0AAACrQYF//+p3EXpvebZSLeWLNgg2SPu73gy"
      + "NjQgLSBjb3JlIDE2NSByMzIyMiBiMzU2MDVhIC0gSC4yNjQvTVBFRy00IEFWQyBjb2RlYyAtIENvcHlsZWZ0IDIwMDMtMjAyNSAtIGh0dHA6Ly93d3cudmlkZW9sYW4u"
      + "b3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFjPTEgcmVmPTMgZGVibG9jaz0xOjA6MCBhbmFseXNlPTB4MzoweDExMyBtZT1oZXggc3VibWU9NyBwc3k9MSBwc3lf"
      + "cmQ9MS4wMDowLjAwIG1peGVkX3JlZj0xIG1lX3JhbmdlPTE2IGNocm9tYV9tZT0xIHRyZWxsaXM9MSA4eDhkY3Q9MSBjcW09MCBkZWFkem9uZT0yMSwxMSBmYXN0X3Bz"
      + "a2lwPTEgY2hyb21hX3FwX29mZnNldD0tMiB0aHJlYWRzPTEgbG9va2FoZWFkX3RocmVhZHM9MSBzbGljZWRfdGhyZWFkcz0wIG5yPTAgZGVjaW1hdGU9MSBpbnRlcmxh"
      + "Y2VkPTAgYmx1cmF5X2NvbXBhdD0wIGNvbnN0cmFpbmVkX2ludHJhPTAgYmZyYW1lcz0zIGJfcHlyYW1pZD0yIGJfYWRhcHQ9MSBiX2JpYXM9MCBkaXJlY3Q9MSB3ZWln"
      + "aHRiPTEgb3Blbl9nb3A9MCB3ZWlnaHRwPTIga2V5aW50PTI1MCBrZXlpbnRfbWluPTEgc2NlbmVjdXQ9NDAgaW50cmFfcmVmcmVzaD0wIHJjX2xvb2thaGVhZD00MCBy"
      + "Yz1jcmYgbWJ0cmVlPTEgY3JmPTIzLjAgcWNvbXA9MC42MCBxcG1pbj0wIHFwbWF4PTY5IHFwc3RlcD00IGlwX3JhdGlvPTEuNDAgYXE9MToxLjAwAIAAAAAQZYiEABX/"
      + "/vfJ78Cm69vfgQ=="
  )!

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
      try handle.write(contentsOf: chunk)
      remaining -= Int64(size)
    }
    try replaceItem(temporary, at: url)
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
    try replaceItem(temporary, at: url)
  }

  private func sha256(_ url: URL) throws -> String {
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
