import CryptoKit
import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import PDFKit
import QuickLookThumbnailing
import SynoraDomain
import UniformTypeIdentifiers

public enum AssetImportError: Error, Equatable, Sendable {
  case sourceMissing
  case sourceUnreadable
  case destinationUnavailable
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

public enum AssetImportSource: Hashable, Sendable {
  case file(URL)

  public var fileURL: URL {
    switch self {
    case .file(let url): url
    }
  }
}

public enum AssetPreviewKind: String, Codable, Hashable, Sendable {
  case image, video, audio, pdf, file
}

public struct AssetPreview: Codable, Hashable, Sendable {
  public let kind: AssetPreviewKind
  public let pixelWidth: Int?
  public let pixelHeight: Int?
  public let pageCount: Int?
  public let thumbnailURL: URL?

  public init(
    kind: AssetPreviewKind,
    pixelWidth: Int? = nil,
    pixelHeight: Int? = nil,
    pageCount: Int? = nil,
    thumbnailURL: URL? = nil
  ) {
    self.kind = kind
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.pageCount = pageCount
    self.thumbnailURL = thumbnailURL
  }
}

public final class AssetStore: @unchecked Sendable {
  public let rootURL: URL
  private let chunkSize: Int
  private let previewGate = DispatchSemaphore(value: 2)
  private let previewLock = NSLock()
  private var previewCache: [String: AssetPreview] = [:]

  public init(rootURL: URL, chunkSize: Int = 1024 * 1024) throws {
    guard chunkSize > 0 else { throw AssetImportError.invalidChunkSize }
    self.rootURL = rootURL
    self.chunkSize = chunkSize
    try FileManager.default.createDirectory(
      at: rootURL.appendingPathComponent("sha256"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: rootURL.appendingPathComponent("staging"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: rootURL.appendingPathComponent("previews"), withIntermediateDirectories: true)
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
    guard sourceURL.isFileURL else { throw AssetImportError.sourceUnreadable }
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      throw AssetImportError.sourceMissing
    }
    guard (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else {
      throw AssetImportError.sourceUnreadable
    }
    let stagingURL = rootURL
      .appendingPathComponent("staging")
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: stagingURL) }
    guard FileManager.default.createFile(atPath: stagingURL.path, contents: nil) else {
      throw AssetImportError.destinationUnavailable
    }
    let totalBytes = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? NSNumber)?.int64Value
    let input: FileHandle
    do { input = try FileHandle(forReadingFrom: sourceURL) }
    catch { throw AssetImportError.sourceUnreadable }
    let output: FileHandle
    do { output = try FileHandle(forWritingTo: stagingURL) }
    catch {
      try? input.close()
      throw AssetImportError.destinationUnavailable
    }
    defer {
      try? input.close()
      try? output.close()
    }

    var hasher = SHA256()
    var bytesCopied: Int64 = 0
    while true {
      do { try Task.checkCancellation() } catch { throw AssetImportError.cancelled }
      let data: Data
      do {
        data = try input.read(upToCount: chunkSize) ?? Data()
      } catch {
        throw AssetImportError.sourceUnreadable
      }
      guard !data.isEmpty else { break }
      hasher.update(data: data)
      do {
        try output.write(contentsOf: data)
      } catch {
        throw AssetImportError.destinationUnavailable
      }
      bytesCopied += Int64(data.count)
      progress?(AssetImportProgress(bytesCopied: bytesCopied, totalBytes: totalBytes))
    }
    do {
      try output.synchronize()
    } catch {
      throw AssetImportError.destinationUnavailable
    }
    try? output.close()
    let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    let destination = rootURL
      .appendingPathComponent("sha256")
      .appendingPathComponent(String(hash.prefix(2)))
      .appendingPathComponent(hash)
    do {
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    } catch {
      throw AssetImportError.destinationUnavailable
    }
    if !FileManager.default.fileExists(atPath: destination.path) {
      do {
        try FileManager.default.moveItem(at: stagingURL, to: destination)
      } catch {
        guard FileManager.default.fileExists(atPath: destination.path) else {
          throw AssetImportError.destinationUnavailable
        }
      }
    }
    return Asset(
      id: assetID,
      contentHash: hash,
      byteCount: bytesCopied,
      mediaType: Self.mediaType(for: sourceURL.pathExtension),
      originalFilename: sourceURL.lastPathComponent
    )
  }

  public func importFile(
    from source: AssetImportSource,
    assetID: UUID = UUID(),
    progress: (@Sendable (AssetImportProgress) -> Void)? = nil
  ) async throws -> Asset {
    try await importFile(at: source.fileURL, assetID: assetID, progress: progress)
  }

  public func importFiles(
    at sourceURLs: [URL],
    progress: (@Sendable (AssetImportProgress) -> Void)? = nil
  ) async throws -> [Asset] {
    var assets: [Asset] = []
    assets.reserveCapacity(sourceURLs.count)
    // ponytail: serial imports bound memory; add measured parallelism only when throughput matters.
    for sourceURL in sourceURLs {
      assets.append(try await importFile(at: sourceURL, progress: progress))
    }
    return assets
  }

  public func cleanupStaging() throws {
    let staging = rootURL.appendingPathComponent("staging")
    for item in try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) {
      try FileManager.default.removeItem(at: item)
    }
  }

  public func recover() throws {
    try cleanupStaging()
  }

  public func recover(referencedAssets: [Asset]) throws {
    try cleanupStaging()
    let referencedHashes = Set(referencedAssets.map(\.contentHash))
    let contentRoot = rootURL.appendingPathComponent("sha256")
    for prefix in try FileManager.default.contentsOfDirectory(
      at: contentRoot, includingPropertiesForKeys: [.isDirectoryKey])
    where (try? prefix.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
      for file in try FileManager.default.contentsOfDirectory(
        at: prefix, includingPropertiesForKeys: [.isDirectoryKey])
      where (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
        && !referencedHashes.contains(file.lastPathComponent)
      {
        try FileManager.default.removeItem(at: file)
      }
      if (try? FileManager.default.contentsOfDirectory(
        at: prefix, includingPropertiesForKeys: nil).isEmpty) == true {
        try? FileManager.default.removeItem(at: prefix)
      }
    }
  }

  public func preview(for asset: Asset) -> AssetPreview {
    previewLock.lock()
    let cacheKey = asset.id.uuidString
    if let cached = previewCache[cacheKey] {
      previewLock.unlock()
      return cached
    }
    previewLock.unlock()
    previewGate.wait()
    defer { previewGate.signal() }
    let url = fileURL(for: asset)
    let type = UTType(asset.mediaType ?? "")
    if Self.isImage(type),
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    {
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
      return cache(AssetPreview(
        kind: .image, pixelWidth: width, pixelHeight: height,
        thumbnailURL: writeThumbnail(
          image: CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
        ] as CFDictionary), hash: asset.contentHash)), key: cacheKey)
    }
    if Self.isPDF(type), let document = PDFDocument(url: url) {
      return cache(AssetPreview(
        kind: .pdf, pageCount: document.pageCount,
        thumbnailURL: document.page(at: 0).flatMap {
          writeThumbnail(image: pdfThumbnail(for: $0), hash: asset.contentHash)
        }), key: cacheKey)
    }
    if Self.isMovie(type) {
      return cache(AssetPreview(kind: .video), key: cacheKey)
    }
    if Self.isAudio(type) {
      return cache(AssetPreview(kind: .audio), key: cacheKey)
    }
    return cache(AssetPreview(kind: .file), key: cacheKey)
  }

  public func thumbnailURL(
    for asset: Asset,
    size: CGSize = CGSize(width: 320, height: 320)
  ) async -> URL? {
    let current = preview(for: asset)
    if let thumbnailURL = current.thumbnailURL { return thumbnailURL }
    let type = UTType(asset.mediaType ?? "")
    let image: CGImage?
    if Self.isMovie(type) {
      image = await videoThumbnail(at: fileURL(for: asset))
    } else {
      image = try? await quickLookThumbnail(at: fileURL(for: asset), size: size)
    }
    guard let thumbnailURL = writeThumbnail(image: image, hash: asset.contentHash) else {
      return nil
    }
    _ = cache(AssetPreview(
      kind: current.kind,
      pixelWidth: current.pixelWidth,
      pixelHeight: current.pixelHeight,
      pageCount: current.pageCount,
      thumbnailURL: thumbnailURL), key: asset.id.uuidString)
    return thumbnailURL
  }

  private func cache(_ preview: AssetPreview, key: String) -> AssetPreview {
    previewLock.lock()
    previewCache[key] = preview
    previewLock.unlock()
    return preview
  }

  private static func mediaType(for pathExtension: String) -> String? {
    let ext = pathExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
    switch ext {
    case "png": return UTType.png.identifier
    case "jpg", "jpeg": return UTType.jpeg.identifier
    case "gif": return UTType.gif.identifier
    case "heic": return UTType.heic.identifier
    case "tif", "tiff": return UTType.tiff.identifier
    case "bmp": return UTType.bmp.identifier
    case "webp": return UTType.webP.identifier
    case "pdf": return UTType.pdf.identifier
    case "mov": return UTType.quickTimeMovie.identifier
    case "mp4", "m4v": return UTType.mpeg4Movie.identifier
    case "mp3": return UTType.mp3.identifier
    case "wav": return UTType.wav.identifier
    case "m4a": return UTType.mpeg4Audio.identifier
    case "aif", "aiff": return UTType.aiff.identifier
    default: break
    }
    return UTType(filenameExtension: ext)?.identifier
  }

  private static func isImage(_ type: UTType?) -> Bool {
    guard let type else { return false }
    return [UTType.image, UTType.png, UTType.jpeg, UTType.gif, UTType.heic, UTType.tiff, UTType.bmp, UTType.webP]
      .contains(type) || type.conforms(to: .image)
  }

  private static func isPDF(_ type: UTType?) -> Bool {
    guard let type else { return false }
    return type == .pdf || type.conforms(to: .pdf)
  }

  private static func isMovie(_ type: UTType?) -> Bool {
    guard let type else { return false }
    return [UTType.movie, UTType.quickTimeMovie, UTType.mpeg4Movie].contains(type)
      || type.conforms(to: .movie)
  }

  private static func isAudio(_ type: UTType?) -> Bool {
    guard let type else { return false }
    return [UTType.audio, UTType.mp3, UTType.wav, UTType.mpeg4Audio, UTType.aiff].contains(type)
      || type.conforms(to: .audio)
  }

  private func writeThumbnail(image: CGImage?, hash: String) -> URL? {
    guard let image else { return nil }
    let destination = rootURL.appendingPathComponent("previews").appendingPathComponent("\(hash).png")
    if FileManager.default.fileExists(atPath: destination.path) { return destination }
    let staging = destination
      .deletingLastPathComponent()
      .appendingPathComponent(".\(hash).\(UUID().uuidString).staging")
    defer { try? FileManager.default.removeItem(at: staging) }
    guard let writer = CGImageDestinationCreateWithURL(
      staging as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(writer, image, nil)
    guard CGImageDestinationFinalize(writer) else {
      return nil
    }
    if !FileManager.default.fileExists(atPath: destination.path) {
      do { try FileManager.default.moveItem(at: staging, to: destination) }
      catch { guard FileManager.default.fileExists(atPath: destination.path) else { return nil } }
    }
    return destination
  }

  private func pdfThumbnail(for page: PDFPage) -> CGImage? {
    let bounds = page.bounds(for: .mediaBox)
    guard bounds.width > 0, bounds.height > 0 else { return nil }
    let scale = min(320 / bounds.width, 320 / bounds.height)
    let width = max(Int(bounds.width * scale), 1)
    let height = max(Int(bounds.height * scale), 1)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.setFillColor(CGColor.white)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.saveGState()
    context.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: context)
    context.restoreGState()
    return context.makeImage()
  }

  private func quickLookThumbnail(at url: URL, size: CGSize) async throws -> CGImage {
    let request = QLThumbnailGenerator.Request(
      fileAt: url, size: size, scale: 1, representationTypes: .thumbnail)
    return try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
  }

  private func videoThumbnail(at url: URL) async -> CGImage? {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    return await withCheckedContinuation { continuation in
      generator.generateCGImageAsynchronously(for: .zero) { image, _, _ in
        continuation.resume(returning: image)
      }
    }
  }

}
