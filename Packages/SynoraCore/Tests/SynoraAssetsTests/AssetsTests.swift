import Foundation
import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import SynoraAssets

@Test
func assetStoreHashesDeduplicatesAndCleansStaging() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-assets-\(UUID().uuidString)", isDirectory: true)
  let source = root.appendingPathComponent("photo.txt")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  try Data("hello🙂".utf8).write(to: source)
  defer { try? FileManager.default.removeItem(at: root) }

  let store = try AssetStore(rootURL: root.appendingPathComponent("assets"))
  let first = try await store.importFile(at: source)
  let second = try await store.importFile(at: source)
  #expect(first.contentHash == second.contentHash)
  #expect(first.byteCount == Int64(Data("hello🙂".utf8).count))
  #expect(FileManager.default.fileExists(atPath: store.fileURL(for: first).path))
  try store.cleanupStaging()
  #expect(try FileManager.default.contentsOfDirectory(
    at: store.rootURL.appendingPathComponent("staging"), includingPropertiesForKeys: nil).isEmpty)
}

@Test
func assetStoreReportsCancellationWithoutLeavingStagingFiles() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-assets-\(UUID().uuidString)", isDirectory: true)
  let source = root.appendingPathComponent("large.bin")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  try Data(repeating: 0xA5, count: 2_000_000).write(to: source)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = try AssetStore(rootURL: root.appendingPathComponent("assets"), chunkSize: 1024)
  let task = Task { try await store.importFile(at: source) }
  task.cancel()
  do {
    _ = try await task.value
    Issue.record("cancelled import unexpectedly succeeded")
  } catch let error as AssetImportError {
    #expect(error == .cancelled)
  }
  try store.cleanupStaging()
}

@Test
func assetStoreUsesContentAddressingAndRecoveryKeepsReferencedFiles() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-assets-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let firstDirectory = root.appendingPathComponent("first", isDirectory: true)
  let secondDirectory = root.appendingPathComponent("second", isDirectory: true)
  try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
  let firstSource = firstDirectory.appendingPathComponent("same.txt")
  let sameContent = root.appendingPathComponent("renamed.txt")
  let otherSource = secondDirectory.appendingPathComponent("same.txt")
  try Data("same".utf8).write(to: firstSource)
  try Data("same".utf8).write(to: sameContent)
  try Data("other".utf8).write(to: otherSource)
  let store = try AssetStore(rootURL: root.appendingPathComponent("assets"))
  let first = try await store.importFile(from: .file(firstSource))
  let renamed = try await store.importFile(at: sameContent)
  let other = try await store.importFiles(at: [otherSource])[0]
  #expect(first.contentHash == renamed.contentHash)
  #expect(first.contentHash != other.contentHash)
  #expect(store.fileURL(for: first) == store.fileURL(for: renamed))
  #expect(first.originalFilename == "same.txt")
  #expect(renamed.originalFilename == "renamed.txt")

  let abandoned = store.rootURL.appendingPathComponent("staging/abandoned")
  try Data("stale".utf8).write(to: abandoned)
  try store.recover(referencedAssets: [first])
  #expect(FileManager.default.fileExists(atPath: store.fileURL(for: first).path))
  #expect(!FileManager.default.fileExists(atPath: store.fileURL(for: other).path))
  #expect(!FileManager.default.fileExists(atPath: abandoned.path))
}

@Test
func assetStoreRejectsMissingDirectoriesAndCachesImagePreview() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("synora-assets-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  #expect(throws: AssetImportError.invalidChunkSize) {
    try AssetStore(rootURL: root.appendingPathComponent("invalid"), chunkSize: 0)
  }
  let store = try AssetStore(rootURL: root.appendingPathComponent("assets"))
  do {
    _ = try await store.importFile(at: root.appendingPathComponent("missing.bin"))
    Issue.record("missing source unexpectedly imported")
  } catch let error as AssetImportError {
    #expect(error == .sourceMissing)
  }
  let directory = root.appendingPathComponent("folder", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  do {
    _ = try await store.importFile(at: directory)
    Issue.record("directory unexpectedly imported")
  } catch let error as AssetImportError {
    #expect(error == .sourceUnreadable)
  }

  let source = root.appendingPathComponent("image.png")
  guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
      data: nil, width: 2, height: 3, bitsPerComponent: 8, bytesPerRow: 8,
      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
    let image = context.makeImage(),
    let writer = CGImageDestinationCreateWithURL(
      source as CFURL, UTType.png.identifier as CFString, 1, nil)
  else {
    Issue.record("could not create image fixture")
    return
  }
  CGImageDestinationAddImage(writer, image, nil)
  #expect(CGImageDestinationFinalize(writer))
  let asset = try await store.importFile(at: source)
  let preview = store.preview(for: asset)
  #expect(preview.kind == .image)
  #expect(preview.pixelWidth == 2)
  #expect(preview.pixelHeight == 3)
  #expect(preview.thumbnailURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
  #expect(store.preview(for: asset) == preview)
}
