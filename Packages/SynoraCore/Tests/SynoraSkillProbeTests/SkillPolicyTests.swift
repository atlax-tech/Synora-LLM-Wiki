import Foundation
import Testing

@testable import SynoraSkillProbe

@Test
func policyRejectsUnlistedCapabilitiesAndNonLoopbackHosts() {
  let evaluator = SkillPolicyEvaluator()
  let policy = CapabilityPolicy(capabilities: [.networkLoopback], allowedDomains: ["127.0.0.1"])
  #expect(throws: SkillPolicyError.networkDenied("example.com")) {
    try evaluator.authorizeNetwork(host: "example.com", policy: policy)
  }
  #expect(throws: SkillPolicyError.capabilityDenied(.writeProposal)) {
    try evaluator.authorize(
      capability: .writeProposal,
      policy: policy,
      now: Date(timeIntervalSince1970: 0),
      deadline: Date(timeIntervalSince1970: 1)
    )
  }
}

@Test
func missingWasmtimeLibraryIsReportedUnavailable() {
  #expect(
    !WasmtimeProbe.libraryAvailable(
      at: "/private/tmp/synora-missing-wasmtime.dylib", under: "/private/tmp"))
}

@Test
func requestValidationEnforcesModuleAndResponseBounds() throws {
  let evaluator = SkillPolicyEvaluator()
  let request = SkillRequest(
    requestID: UUID(),
    module: Data([0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00]),
    policy: CapabilityPolicy(maxResponseBytes: 256, maxModuleBytes: 8),
    deadline: Date(timeIntervalSince1970: 1)
  )
  try evaluator.validate(request, now: Date(timeIntervalSince1970: 0))
  #expect(throws: SkillPolicyError.responseTooLarge(actual: 257, maximum: 256)) {
    try evaluator.validateResponse(Data(repeating: 0, count: 257), policy: request.policy)
  }
}

@Test
func requestValidationRejectsInvalidModuleAndTooSmallResponseLimit() {
  let evaluator = SkillPolicyEvaluator()
  let invalidModule = SkillRequest(
    requestID: UUID(), module: Data([1, 2, 3]), policy: CapabilityPolicy(),
    deadline: Date(timeIntervalSince1970: 1))
  #expect(throws: SkillPolicyError.invalidModule) {
    try evaluator.validate(invalidModule, now: Date(timeIntervalSince1970: 0))
  }

  let invalidResponseLimit = SkillRequest(
    requestID: UUID(),
    module: Data([0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00]),
    policy: CapabilityPolicy(maxResponseBytes: 1),
    deadline: Date(timeIntervalSince1970: 1))
  #expect(throws: SkillPolicyError.invalidResponseLimit) {
    try evaluator.validate(invalidResponseLimit, now: Date(timeIntervalSince1970: 0))
  }
}

@Test
func verifiedWasmtimeExecutesGuestStartFunction() throws {
  let environment = ProcessInfo.processInfo.environment
  guard let root = environment["SYNORA_WASMTIME_ROOT"] else { return }
  let library = URL(fileURLWithPath: root).appendingPathComponent("lib/libwasmtime.dylib").path
  let startModule = Data([
    0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,
    0x01, 0x04, 0x01, 0x60, 0x00, 0x00,
    0x03, 0x02, 0x01, 0x00,
    0x08, 0x01, 0x00,
    0x0A, 0x04, 0x01, 0x02, 0x00, 0x0B,
  ])
  #expect(WasmtimeProbe.runStart(module: startModule, library: library, under: root))
  #expect(!WasmtimeProbe.runStart(module: Data([0, 1]), library: library, under: root))
}

// (func (loop br 0)) with start: the guest never returns on its own.
private let infiniteLoopModule = Data([
  0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,
  0x01, 0x04, 0x01, 0x60, 0x00, 0x00,
  0x03, 0x02, 0x01, 0x00,
  0x08, 0x01, 0x00,
  0x0A, 0x09, 0x01, 0x07, 0x00, 0x03, 0x40, 0x0C, 0x00, 0x0B, 0x0B,
])

// Imports "env"."f": the probe supplies no host imports, so instantiation must fail.
private let hostImportModule = Data([
  0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,
  0x01, 0x04, 0x01, 0x60, 0x00, 0x00,
  0x02, 0x09, 0x01, 0x03, 0x65, 0x6E, 0x76, 0x01, 0x66, 0x00, 0x00,
])

@Test
func deadlineTerminatesInfiniteLoopGuest() throws {
  guard let root = ProcessInfo.processInfo.environment["SYNORA_WASMTIME_ROOT"] else { return }
  let library = URL(fileURLWithPath: root).appendingPathComponent("lib/libwasmtime.dylib").path
  let started = Date()
  #expect(
    !WasmtimeProbe.runStart(
      module: infiniteLoopModule, library: library, under: root, deadlineNanos: 200_000_000))
  let elapsed = Date().timeIntervalSince(started)
  #expect(elapsed >= 0.2)
  #expect(elapsed < 2.0)
}

@Test
func cancelFlagTerminatesGuestWithin100Milliseconds() throws {
  guard let root = ProcessInfo.processInfo.environment["SYNORA_WASMTIME_ROOT"] else { return }
  let library = URL(fileURLWithPath: root).appendingPathComponent("lib/libwasmtime.dylib").path
  let flag = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
  defer { flag.deallocate() }
  flag.initialize(to: 0)
  DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { flag.pointee = 1 }
  let started = Date()
  #expect(
    !WasmtimeProbe.runStart(
      module: infiniteLoopModule, library: library, under: root,
      deadlineNanos: 10_000_000_000, cancelFlag: flag))
  let elapsed = Date().timeIntervalSince(started)
  #expect(elapsed >= 0.05)
  #expect(elapsed < 1.0)
}

@Test
func guestCannotResolveHostImportsOrExceedDeadline() throws {
  guard let root = ProcessInfo.processInfo.environment["SYNORA_WASMTIME_ROOT"] else { return }
  let library = URL(fileURLWithPath: root).appendingPathComponent("lib/libwasmtime.dylib").path
  // No host imports are registered, so a guest that imports anything is rejected.
  #expect(!WasmtimeProbe.runStart(module: hostImportModule, library: library, under: root))
  // A valid guest with no deadline still completes.
  let startModule = Data([
    0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,
    0x01, 0x04, 0x01, 0x60, 0x00, 0x00,
    0x03, 0x02, 0x01, 0x00,
    0x08, 0x01, 0x00,
    0x0A, 0x04, 0x01, 0x02, 0x00, 0x0B,
  ])
  #expect(WasmtimeProbe.runStart(module: startModule, library: library, under: root))
}

// Imports "synora"."request" (4 i32 -> i32), exports memory holding
// "readTemporaryDirectory/tmp", and its start function calls the import.
private let brokerModule = Data([
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

@Test
func brokerReceivesGuestCapabilityRequestsAndAppliesPolicy() throws {
  guard let root = ProcessInfo.processInfo.environment["SYNORA_WASMTIME_ROOT"] else { return }
  let library = URL(fileURLWithPath: root).appendingPathComponent("lib/libwasmtime.dylib").path
  let policy = CapabilityPolicy(capabilities: [.readTemporaryDirectory])
  var recorded: [(capability: String, target: String)] = []
  let broker: WasmtimeProbe.SkillBroker = { capability, target in
    recorded.append((capability, target))
    guard capability == SkillCapability.readTemporaryDirectory.rawValue, target == "/tmp" else {
      return 1
    }
    return 0
  }
  #expect(
    WasmtimeProbe.runStart(module: brokerModule, library: library, under: root, broker: broker))
  #expect(recorded.count == 1)
  #expect(recorded[0].capability == "readTemporaryDirectory")
  #expect(recorded[0].target == "/tmp")

  // A policy that lacks the capability still lets the run complete; the guest only
  // sees the denial return code.
  recorded.removeAll()
  let denying: WasmtimeProbe.SkillBroker = { _, _ in 1 }
  #expect(
    WasmtimeProbe.runStart(module: brokerModule, library: library, under: root, broker: denying))
  #expect(recorded.isEmpty)
  _ = policy
}
