import Foundation
import ImageIO
import Testing

@testable import SynoraBenchmark

@Test
func smokeGenerationIsDeterministicAndResumable() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let secondRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {
    try? FileManager.default.removeItem(at: root)
    try? FileManager.default.removeItem(at: secondRoot)
  }
  let generator = BenchmarkGenerator()
  let first = try generator.generate(profile: .smoke, output: root)
  let second = try generator.generate(profile: .smoke, output: secondRoot)
  #expect(first == second)
  for path in ["manifest.json", "records.jsonl", "blocks.jsonl", "assets/payload.tiff"] {
    #expect(
      try Data(contentsOf: root.appendingPathComponent(path))
        == Data(contentsOf: secondRoot.appendingPathComponent(path))
    )
  }
  let resumed = try generator.generate(profile: .smoke, output: root, resume: true)
  #expect(resumed == first)
  try generator.verify(first, in: root)
}

@Test
func smokeAssetHasAReadableTIFFHeader() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let manifest = try BenchmarkGenerator().generate(profile: .smoke, output: root)
  let asset = root.appendingPathComponent("assets/payload.tiff")
  let source = CGImageSourceCreateWithURL(asset as CFURL, nil)
  #expect(source != nil)
  #expect(CGImageSourceGetCount(source!) == 1)
  #expect(manifest.logicalAssetBytes == 1024 * 1024)
}

@Test
func verifyRejectsTamperedManifestShapeAndPhysicalBytes() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let generator = BenchmarkGenerator()
  let manifest = try generator.generate(profile: .smoke, output: root)

  let missingFileManifest = BenchmarkManifest(
    profile: manifest.profile,
    seed: manifest.seed,
    records: manifest.records,
    blocks: manifest.blocks,
    logicalAssetBytes: manifest.logicalAssetBytes,
    physicalBytes: manifest.physicalBytes,
    files: ["records.jsonl": manifest.files["records.jsonl"]!]
  )
  #expect(throws: BenchmarkError.mismatch("manifest file set does not match profile")) {
    try generator.verify(missingFileManifest, in: root)
  }

  let wrongSizeManifest = BenchmarkManifest(
    profile: manifest.profile,
    seed: manifest.seed,
    records: manifest.records,
    blocks: manifest.blocks,
    logicalAssetBytes: manifest.logicalAssetBytes,
    physicalBytes: manifest.physicalBytes + 1,
    files: manifest.files
  )
  #expect(throws: BenchmarkError.mismatch("manifest physical bytes do not match files")) {
    try generator.verify(wrongSizeManifest, in: root)
  }
}
