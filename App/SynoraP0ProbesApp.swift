import Foundation
import SwiftUI

import SynoraSkillProbe

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
  @State private var skillStatus = "pending"

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
        LabeledContent(
          "TextKit 2 ranges",
          value: TextKit2ProbeResult.fixture.rangesValid ? "valid" : "invalid"
        )
        LabeledContent("Wasmtime XPC", value: skillStatus)
          .accessibilityIdentifier("wasmtime-xpc-status")
      }
      .textSelection(.enabled)

      Text("TextKit 2 editing fixture")
        .font(.headline)
      TextKit2ProbeView(initialText: TextKit2ProbeResult.fixture.text)
        .frame(minHeight: 160)
        .border(.secondary)
    }
    .frame(minWidth: 720, minHeight: 480, alignment: .topLeading)
    .padding()
    .task {
      skillStatus = await AgentServiceProbeClient.runFixture()
    }
  }
}

@objc private protocol AgentServiceProbeProtocol {
  func run(_ request: Data, withReply reply: @escaping (Data) -> Void)
}

private enum AgentServiceProbeClient {
  private struct Result: Decodable {
    let code: String
    let message: String
  }

  static func runFixture() async -> String {
    let connection = NSXPCConnection(serviceName: "tech.atlax.SynoraWiki.P0Probes.AgentProbe")
    connection.remoteObjectInterface = NSXPCInterface(with: AgentServiceProbeProtocol.self)
    connection.resume()
    defer { connection.invalidate() }

    let module = Data([
      0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,
      0x01, 0x04, 0x01, 0x60, 0x00, 0x00,
      0x03, 0x02, 0x01, 0x00,
      0x08, 0x01, 0x00,
      0x0A, 0x04, 0x01, 0x02, 0x00, 0x0B,
    ])
    let request = SkillRequest(
      requestID: UUID(),
      module: module,
      policy: CapabilityPolicy(),
      deadline: Date().addingTimeInterval(10)
    )
    guard let data = try? JSONEncoder().encode(request) else { return "encode failed" }

    return await withCheckedContinuation { continuation in
      let proxy = connection.remoteObjectProxyWithErrorHandler { error in
        continuation.resume(returning: "connection failed: \(error.localizedDescription)")
      }
      guard let service = proxy as? AgentServiceProbeProtocol else {
        continuation.resume(returning: "interface failed")
        return
      }
      service.run(data) { response in
        guard let result = try? JSONDecoder().decode(Result.self, from: response) else {
          continuation.resume(returning: "invalid response")
          return
        }
        continuation.resume(
          returning: result.code == "success" ? "success" : "\(result.code): \(result.message)")
      }
    }
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
