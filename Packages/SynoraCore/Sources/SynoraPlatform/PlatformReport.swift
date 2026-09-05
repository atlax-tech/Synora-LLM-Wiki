import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

public struct PlatformReport: Codable, Sendable {
  public let operatingSystem: String
  public let architecture: String
  public let swiftVersion: String
  public let foundationModels: String

  public static var current: Self {
    #if canImport(FoundationModels)
      let model = SystemLanguageModel.default
      let status =
        model.isAvailable
        ? "available"
        : "unavailable (\(String(describing: model.availability)))"
      let foundationModels = status
    #else
      let foundationModels = "unavailable (framework unavailable)"
    #endif

    return Self(
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      architecture: buildArchitecture,
      swiftVersion: "6.2",
      foundationModels: foundationModels
    )
  }

  private static var buildArchitecture: String {
    #if arch(arm64)
      return "arm64"
    #elseif arch(x86_64)
      return "x86_64"
    #else
      return "unknown"
    #endif
  }
}
