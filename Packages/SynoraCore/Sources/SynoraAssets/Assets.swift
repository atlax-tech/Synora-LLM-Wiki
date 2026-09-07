import CryptoKit
import Foundation
import ImageIO
import PDFKit
import SynoraDomain
import UniformTypeIdentifiers

public enum AssetImportError: Error, Equatable, Sendable {
  case sourceMissing
  case sourceUnreadable
  case cancelled
  case invalidChunkSize
}

public struct AssetImportProgress: Sendable {
  public let bytesCopied: Int64
  public let totalBytes: Int64?

  public init(bytesCopied: Int64, totalBytes: Int64?) {
    self.bytesCopied = bytesCopied
    self.totalBytes = totalBytes
  }
}

public enum AssetPreviewKind: String, Codable, Hashable, Sendable {
  case image, video, audio, pdf, file
}

public struct AssetPreview: Hashable, Sendable {
  public let kind: AssetPreviewKind
  public let pixelWidth: Int?
  public let pixelHeight: Int?
  public let pageCount: Int?

  public init(
    kind: AssetPreviewKind,
    pixelWidth: Int? = nil,
    pixelHeight: Int? = nil,
    pageCount: Int? = nil
  ) {
    self.kind = kind
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.pageCount = pageCount
  }
}

public final class AssetStore: @unchecked Sendable {
  public let rootURL: URL
  private let chunkSize: Int

  public init(rootURL: URL, chunkSize: Int = 1024 * 1024) throws {
    guard chunkSize > 0 else { throw AssetImportError.invalidChunkSize }
    self.rootURL = rootURL
    self.chunkSize = chunkSize
    try FileManager.default.createDirectory(
      at: rootURL.appendingPathComponent("sha256"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: rootURL.appendingPathComponent("staging"), withIntermediateDirectories: true)
  }

  public func fileURL(for asset: Asset) -> URL {
    rootURL
      .appendingPathComponent("sha256")
      .appendingPathComponent(String(asset.contentHash.prefix(2)))
      .appendingPathComponent(asset.contentHash)
  }

  public func importFile(
    at sourceURL: URL,
    assetID: UUID = UUID(),
    progress: (@Sendable (AssetImportProgress) -> Void)? = nil
  ) async throws -> Asset {
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      throw AssetImportError.sourceMissing
    }
    let stagingURL = rootURL.appendingPathComponent("staging").appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: stagingURL) }
    guard FileManager.default.createFile(atPath: stagingURL.path, contents: nil) else {
      throw AssetImportError.sourceUnreadable
    }
    let totalBytes = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? NSNumber)?.int64Value
    let input: FileHandle
    let output: FileHandle
    do {
      input = try FileHandle(forReadingFrom: sourceURL)
      output = try FileHandle(forWritingTo: stagingURL)
    } catch {
      throw AssetImportError.sourceUnreadable
    }
    defer {
      try? input.close()
      try? output.close()
    }

    var hasher = SHA256()
    var bytesCopied: Int64 = 0
    while true {
      do { try Task.checkCancellation() } catch { throw AssetImportError.cancelled }
      guard let data = try input.read(upToCount: chunkSize), !data.isEmpty else { break }
      hasher.update(data: data)
      try output.write(contentsOf: data)
      bytesCopied += Int64(data.count)
      progress?(AssetImportProgress(bytesCopied: bytesCopied, totalBytes: totalBytes))
    }
    try output.synchronize()
    let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    let destination = rootURL
      .appendingPathComponent("sha256")
      .appendingPathComponent(String(hash.prefix(2)))
      .appendingPathComponent(hash)
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.moveItem(at: stagingURL, to: destination)
    }
    return Asset(
      id: assetID,
      contentHash: hash,
      byteCount: bytesCopied,
      mediaType: UTType(filenameExtension: sourceURL.pathExtension)?.identifier,
      originalFilename: sourceURL.lastPathComponent
    )
  }

  public func cleanupStaging() throws {
    let staging = rootURL.appendingPathComponent("staging")
    for item in try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) {
      try FileManager.default.removeItem(at: item)
    }
  }

  public func preview(for asset: Asset) -> AssetPreview {
    let url = fileURL(for: asset)
    let type = UTType(asset.mediaType ?? "")
    if type?.conforms(to: UTType.image) == true,
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    {
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
      return AssetPreview(kind: .image, pixelWidth: width, pixelHeight: height)
    }
    if type?.conforms(to: UTType.pdf) == true, let document = PDFDocument(url: url) {
      return AssetPreview(kind: .pdf, pageCount: document.pageCount)
    }
    if type?.conforms(to: UTType.movie) == true { return AssetPreview(kind: .video) }
    if type?.conforms(to: UTType.audio) == true { return AssetPreview(kind: .audio) }
    return AssetPreview(kind: .file)
  }
}
