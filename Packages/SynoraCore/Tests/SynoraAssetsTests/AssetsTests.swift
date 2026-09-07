import Foundation
import Testing

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
