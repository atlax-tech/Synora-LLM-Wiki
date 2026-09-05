import Foundation
import SynoraBenchmark

enum Arguments {
  static func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let profile =
  BenchmarkProfile(rawValue: Arguments.value(after: "--profile", in: arguments) ?? "smoke")
  ?? .smoke
let seed =
  UInt64(Arguments.value(after: "--seed", in: arguments) ?? "20260905")
  ?? BenchmarkGenerator.defaultSeed
let outputPath = Arguments.value(after: "--output", in: arguments) ?? ".build/benchmark"
let resume = arguments.contains("--resume")

do {
  let manifest = try BenchmarkGenerator().generate(
    profile: profile,
    seed: seed,
    output: URL(fileURLWithPath: outputPath, isDirectory: true),
    resume: resume
  )
  let data = try JSONEncoder().encode(manifest)
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write(Data([0x0A]))
} catch {
  fputs("benchmark generation failed: \(error)\n", stderr)
  exit(1)
}
