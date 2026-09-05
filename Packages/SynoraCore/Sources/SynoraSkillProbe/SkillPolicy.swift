import CWasmtimeShim
import Foundation

public enum SkillCapability: String, Codable, CaseIterable, Sendable {
  case readTemporaryDirectory
  case networkLoopback
  case writeProposal
}

public struct CapabilityPolicy: Codable, Hashable, Sendable {
  public let capabilities: Set<SkillCapability>
  public let allowedDomains: Set<String>
  public let maxResponseBytes: Int

  public init(
    capabilities: Set<SkillCapability> = [],
    allowedDomains: Set<String> = [],
    maxResponseBytes: Int = 1_048_576
  ) {
    self.capabilities = capabilities
    self.allowedDomains = allowedDomains
    self.maxResponseBytes = max(0, maxResponseBytes)
  }

  public func permits(_ capability: SkillCapability) -> Bool {
    capabilities.contains(capability)
  }

  public func permitsNetwork(host: String) -> Bool {
    permits(.networkLoopback) && allowedDomains.contains(host) && host == "127.0.0.1"
  }
}

public struct SkillRequest: Codable, Hashable, Sendable {
  public let requestID: UUID
  public let module: Data
  public let policy: CapabilityPolicy
  public let deadline: Date

  public init(requestID: UUID, module: Data, policy: CapabilityPolicy, deadline: Date) {
    self.requestID = requestID
    self.module = module
    self.policy = policy
    self.deadline = deadline
  }
}

public enum SkillFailure: String, Codable, Sendable {
  case rejected
  case deadlineExceeded
  case cancelled
  case runtimeFailure
}

public enum SkillResult: Codable, Equatable, Sendable {
  case success(Data)
  case failure(SkillFailure, message: String)
}

public enum SkillPolicyError: Error, Equatable, Sendable {
  case capabilityDenied(SkillCapability)
  case networkDenied(String)
  case deadlineExceeded
}

public struct SkillPolicyEvaluator: Sendable {
  public init() {}

  public func authorize(
    capability: SkillCapability,
    policy: CapabilityPolicy,
    now: Date,
    deadline: Date
  ) throws {
    guard now <= deadline else { throw SkillPolicyError.deadlineExceeded }
    guard policy.permits(capability) else { throw SkillPolicyError.capabilityDenied(capability) }
  }

  public func authorizeNetwork(host: String, policy: CapabilityPolicy) throws {
    guard policy.permitsNetwork(host: host) else { throw SkillPolicyError.networkDenied(host) }
  }
}

public enum WasmtimeProbe {
  public static func libraryAvailable(at path: String) -> Bool {
    path.withCString { synora_wasmtime_library_available($0) }
  }
}
