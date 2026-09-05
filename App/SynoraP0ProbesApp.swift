import SwiftUI

#if canImport(FoundationModels)
  import FoundationModels
#endif

@main
struct SynoraP0ProbesApp: App {
  var body: some Scene {
    WindowGroup("Synora P0 Probes") {
      P0ProbeOverview(report: .current)
    }
  }
}

private struct P0ProbeOverview: View {
  let report: PlatformProbeReport

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Synora P0 Probes")
        .font(.title)
      Text("Engineering-only host")
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 8) {
        LabeledContent("Operating system", value: report.operatingSystem)
        LabeledContent("Architecture", value: report.architecture)
        LabeledContent("Swift toolchain", value: report.swiftVersion)
        LabeledContent("Foundation Models", value: report.foundationModels)
      }
      .textSelection(.enabled)
    }
    .frame(minWidth: 720, minHeight: 480, alignment: .topLeading)
    .padding()
  }
}

private struct PlatformProbeReport {
  let operatingSystem: String
  let architecture: String
  let swiftVersion: String
  let foundationModels: String

  static var current: Self {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        let model = SystemLanguageModel.default
        let status =
          model.isAvailable
          ? "available"
          : "unavailable (\(String(describing: model.availability)))"
        return Self(
          operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
          architecture: buildArchitecture,
          swiftVersion: "6.2",
          foundationModels: status
        )
      }
    #endif

    return Self(
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      architecture: buildArchitecture,
      swiftVersion: "6.2",
      foundationModels: "unavailable (unsupported SDK)"
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
