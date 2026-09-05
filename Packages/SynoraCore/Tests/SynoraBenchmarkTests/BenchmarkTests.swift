import Foundation
import ImageIO
import Testing

@testable import SynoraBenchmark

@Test
func smokeGenerationIsDeterministicAndResumable() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let generator = BenchmarkGenerator()
  let first = try generator.generate(profile: .smoke, output: root)
  let second = try generator.generate(profile: .smoke, output: root)
  #expect(first == second)
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
