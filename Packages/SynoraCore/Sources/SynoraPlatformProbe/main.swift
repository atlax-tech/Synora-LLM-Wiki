import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

struct PlatformReport: Encodable {
  let operatingSystem: String
  let architecture: String
  let swiftVersion: String
  let foundationModels: String
}

let foundationModels: String
#if canImport(FoundationModels)
  if #available(macOS 26.0, *) {
    let model = SystemLanguageModel.default
    foundationModels =
      model.isAvailable
      ? "available"
      : "unavailable (\(String(describing: model.availability)))"
  } else {
    foundationModels = "unavailable (unsupported SDK)"
  }
#else
  foundationModels = "unavailable (framework unavailable)"
#endif

let report = PlatformReport(
  operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
  architecture: "arm64",
  swiftVersion: "6.2",
  foundationModels: foundationModels
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let data = try encoder.encode(report)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data([0x0A]))
