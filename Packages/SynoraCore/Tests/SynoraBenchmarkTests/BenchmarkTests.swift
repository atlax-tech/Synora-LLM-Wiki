import AVFoundation
import Foundation
import ImageIO
import PDFKit
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
  for path in [
    "manifest.json", "records.jsonl", "blocks.jsonl", "assets/payload.bin",
    "assets/preview.png", "assets/preview.pdf", "assets/preview.wav", "assets/preview.mp4",
  ] {
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
func smokeMediaFixturesOpenInSystemFrameworks() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let manifest = try BenchmarkGenerator().generate(profile: .smoke, output: root)
  let image = root.appendingPathComponent(BenchmarkGenerator.mediaPaths["image"]!)
  let source = CGImageSourceCreateWithURL(image as CFURL, nil)
  #expect(source != nil)
  #expect(CGImageSourceGetCount(source!) == 1)
  let pdf = root.appendingPathComponent(BenchmarkGenerator.mediaPaths["document"]!)
  #expect(PDFDocument(url: pdf)?.pageCount == 1)
  let audio = root.appendingPathComponent(BenchmarkGenerator.mediaPaths["audio"]!)
  #expect(try AVAudioFile(forReading: audio).length == 8)
  let video = AVURLAsset(url: root.appendingPathComponent(BenchmarkGenerator.mediaPaths["video"]!))
  #expect(try await video.load(.tracks).contains { $0.mediaType == .video })
  #expect(manifest.logicalAssetBytes == 1024 * 1024)
}

@Test
func fullProfileKeepsTheExactP008CorpusShape() {
  #expect(BenchmarkProfile.full.recordCount == 10_000)
  #expect(BenchmarkProfile.full.blockCount == 100_000)
  #expect(BenchmarkProfile.full.assetBytes == 20 * 1024 * 1024 * 1024)
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

  let records = root.appendingPathComponent("records.jsonl")
  var tampered = try Data(contentsOf: records)
  tampered.append(0x20)
  try tampered.write(to: records, options: .atomic)
  #expect(throws: BenchmarkError.mismatch("checksum mismatch: records.jsonl")) {
    try generator.verify(manifest, in: root)
  }
}
