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
      HStack {
        Button("Insert attachment") {
          NotificationCenter.default.post(name: .synoraInsertAttachment, object: nil)
        }
        .accessibilityIdentifier("insert-attachment")
        Text("Native NSTextView undo, redo, copy, paste and delete remain enabled.")
          .foregroundStyle(.secondary)
      }
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
  func cancel(_ requestID: String, withReply reply: @escaping (Bool) -> Void)
}

private enum AgentServiceProbeClient {
  private struct Result: Decodable, Sendable {
    let code: String
    let message: String
  }

  static func runFixture() async -> String {
    let success = await runRequest(
      SkillRequest(
        requestID: UUID(), module: startModule, policy: CapabilityPolicy(),
        deadline: Date().addingTimeInterval(10)))
    let broker = await runRequest(
      SkillRequest(
        requestID: UUID(), module: brokerModule,
        policy: CapabilityPolicy(capabilities: [.readTemporaryDirectory]),
        deadline: Date().addingTimeInterval(10)))
    let network = await runRequest(
      SkillRequest(
        requestID: UUID(), module: networkModule,
        policy: CapabilityPolicy(
          capabilities: [.networkLoopback], allowedDomains: ["127.0.0.1"]),
        deadline: Date().addingTimeInterval(10)))
    let deniedNetwork = await runRequest(
      SkillRequest(
        requestID: UUID(), module: networkModule,
        policy: CapabilityPolicy(
          capabilities: [.networkLoopback], allowedDomains: ["example.com"]),
        deadline: Date().addingTimeInterval(10)))
    let cancelled = await runCancellationFixture()
    let status =
      success.code == "success" && broker.code == "success" && network.code == "success"
        && deniedNetwork.code == "runtimeFailure" && cancelled
      ? "success"
      : "fixture failed: success=\(success.code), broker=\(broker.code), network=\(network.code), denied=\(deniedNetwork.code), cancelled=\(cancelled)"
    writeFixtureReport(
      status, cancelled: cancelled,
      broker: broker.code == "success" && network.code == "success"
        && deniedNetwork.code == "runtimeFailure")
    return status
  }

  private static let startModule = Data([
    0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,
    0x01, 0x04, 0x01, 0x60, 0x00, 0x00,
    0x03, 0x02, 0x01, 0x00,
    0x08, 0x01, 0x00,
    0x0A, 0x04, 0x01, 0x02, 0x00, 0x0B,
  ])

  private static let brokerModule = Data([
    0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,
    0x01, 0x0C, 0x02, 0x60, 0x00, 0x00, 0x60, 0x04, 0x7F, 0x7F, 0x7F, 0x7F, 0x01, 0x7F,
    0x02, 0x12, 0x01, 0x06, 0x73, 0x79, 0x6E, 0x6F, 0x72, 0x61,
    0x07, 0x72, 0x65, 0x71, 0x75, 0x65, 0x73, 0x74, 0x00, 0x01,
    0x03, 0x02, 0x01, 0x00,
    0x05, 0x03, 0x01, 0x00, 0x01,
    0x07, 0x0A, 0x01, 0x06, 0x6D, 0x65, 0x6D, 0x6F, 0x72, 0x79, 0x02, 0x00,
    0x08, 0x01, 0x01,
    0x0A, 0x0F, 0x01, 0x0D, 0x00, 0x41, 0x00, 0x41, 0x16, 0x41, 0x16, 0x41, 0x04, 0x10, 0x00,
    0x1A, 0x0B,
    0x0B, 0x20, 0x01, 0x00, 0x41, 0x00, 0x0B, 0x1A,
    0x72, 0x65, 0x61, 0x64, 0x54, 0x65, 0x6D, 0x70, 0x6F, 0x72, 0x61, 0x72, 0x79, 0x44, 0x69,
    0x72, 0x65, 0x63, 0x74, 0x6F, 0x72, 0x79, 0x2F, 0x74, 0x6D, 0x70,
  ])

  // Same host import as brokerModule, but traps when the broker denies the request.
  private static let networkModule = Data([
    0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,
    0x01, 0x0C, 0x02, 0x60, 0x00, 0x00, 0x60, 0x04, 0x7F, 0x7F, 0x7F, 0x7F, 0x01, 0x7F,
    0x02, 0x12, 0x01, 0x06, 0x73, 0x79, 0x6E, 0x6F, 0x72, 0x61,
    0x07, 0x72, 0x65, 0x71, 0x75, 0x65, 0x73, 0x74, 0x00, 0x01,
    0x03, 0x02, 0x01, 0x00,
    0x05, 0x03, 0x01, 0x00, 0x01,
    0x07, 0x0A, 0x01, 0x06, 0x6D, 0x65, 0x6D, 0x6F, 0x72, 0x79, 0x02, 0x00,
    0x08, 0x01, 0x01,
    0x0A, 0x15, 0x01, 0x13, 0x00, 0x41, 0x00, 0x41, 0x0F, 0x41, 0x0F, 0x41, 0x09,
    0x10, 0x00, 0x41, 0x00, 0x47, 0x04, 0x40, 0x00, 0x0B, 0x0B,
    0x0B, 0x1E, 0x01, 0x00, 0x41, 0x00, 0x0B, 0x18,
    0x6E, 0x65, 0x74, 0x77, 0x6F, 0x72, 0x6B, 0x4C, 0x6F, 0x6F, 0x70, 0x62, 0x61, 0x63, 0x6B,
    0x31, 0x32, 0x37, 0x2E, 0x30, 0x2E, 0x30, 0x2E, 0x31,
  ])

  private static let infiniteLoopModule = Data([
    0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,
    0x01, 0x04, 0x01, 0x60, 0x00, 0x00,
    0x03, 0x02, 0x01, 0x00,
    0x08, 0x01, 0x00,
    0x0A, 0x09, 0x01, 0x07, 0x00, 0x03, 0x40, 0x0C, 0x00, 0x0B, 0x0B,
  ])

  private static func makeConnection() -> NSXPCConnection {
    let connection = NSXPCConnection(serviceName: "tech.atlax.SynoraWiki.P0Probes.AgentProbe")
    connection.remoteObjectInterface = NSXPCInterface(with: AgentServiceProbeProtocol.self)
    connection.resume()
    return connection
  }

  private static func runRequest(_ request: SkillRequest) async -> Result {
    let connection = makeConnection()
    defer { connection.invalidate() }
    guard let data = try? JSONEncoder().encode(request) else {
      return Result(code: "rejected", message: "encode failed")
    }
    return await withCheckedContinuation { continuation in
      let proxy = connection.remoteObjectProxyWithErrorHandler { error in
        continuation.resume(
          returning: Result(code: "connectionFailed", message: error.localizedDescription))
      }
      guard let service = proxy as? AgentServiceProbeProtocol else {
        continuation.resume(returning: Result(code: "interfaceFailed", message: "invalid proxy"))
        return
      }
      service.run(data) { response in
        guard let result = try? JSONDecoder().decode(Result.self, from: response) else {
          continuation.resume(
            returning: Result(code: "invalidResponse", message: "invalid response"))
          return
        }
        continuation.resume(returning: result)
      }
    }
  }

  private static func runCancellationFixture() async -> Bool {
    let requestID = UUID()
    let request = SkillRequest(
      requestID: requestID, module: infiniteLoopModule, policy: CapabilityPolicy(),
      deadline: Date().addingTimeInterval(10))
    let running = Task { await runRequest(request) }
    try? await Task.sleep(for: .milliseconds(50))
    let connection = makeConnection()
    let accepted = await withCheckedContinuation { continuation in
      let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
        continuation.resume(returning: false)
      }
      guard let service = proxy as? AgentServiceProbeProtocol else {
        continuation.resume(returning: false)
        return
      }
      service.cancel(requestID.uuidString) { continuation.resume(returning: $0) }
    }
    connection.invalidate()
    let result = await running.value
    return accepted && result.code == "cancelled"
  }

  /// Persists only status and bounded metadata so scripts can verify this run without
  /// needing accessibility access to the window or exposing guest content.
  private static func writeFixtureReport(
    _ status: String, cancelled: Bool, broker: Bool
  ) {
    let report: [String: Any] = [
      "status": status,
      "cancelled": cancelled,
      "broker": broker,
      "pid": ProcessInfo.processInfo.processIdentifier,
      "executable": Bundle.main.executablePath ?? "",
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: report) else { return }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("synora-xpc-fixture.json")
    try? data.write(to: url, options: .atomic)
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
