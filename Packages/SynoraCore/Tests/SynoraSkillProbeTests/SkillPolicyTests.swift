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
  #expect(!WasmtimeProbe.libraryAvailable(at: "/private/tmp/synora-missing-wasmtime.dylib"))
}
