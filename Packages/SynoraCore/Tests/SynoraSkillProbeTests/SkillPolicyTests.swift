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
