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
