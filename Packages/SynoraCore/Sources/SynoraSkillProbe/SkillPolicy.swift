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
  public let maxModuleBytes: Int

  public init(
    capabilities: Set<SkillCapability> = [],
    allowedDomains: Set<String> = [],
    maxResponseBytes: Int = 1_048_576,
    maxModuleBytes: Int = 8 * 1024 * 1024
  ) {
    self.capabilities = capabilities
    self.allowedDomains = allowedDomains
    self.maxResponseBytes = max(0, maxResponseBytes)
    self.maxModuleBytes = max(0, maxModuleBytes)
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
  case responseTooLarge
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
  case invalidModule
  case moduleTooLarge(actual: Int, maximum: Int)
  case invalidResponseLimit
  case responseTooLarge(actual: Int, maximum: Int)
}

public struct SkillPolicyEvaluator: Sendable {
  public static let minimumResponseBytes = 256

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

  public func validate(_ request: SkillRequest, now: Date) throws {
    try authorizeRequestDeadline(now: now, deadline: request.deadline)
    guard request.policy.maxResponseBytes >= Self.minimumResponseBytes else {
      throw SkillPolicyError.invalidResponseLimit
    }
    guard request.module.count <= request.policy.maxModuleBytes else {
      throw SkillPolicyError.moduleTooLarge(
        actual: request.module.count, maximum: request.policy.maxModuleBytes)
    }
    guard request.module.starts(with: [0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00]) else {
      throw SkillPolicyError.invalidModule
    }
  }

  public func validateResponse(_ response: Data, policy: CapabilityPolicy) throws {
    guard response.count <= policy.maxResponseBytes else {
      throw SkillPolicyError.responseTooLarge(
        actual: response.count, maximum: policy.maxResponseBytes)
    }
  }

  private func authorizeRequestDeadline(now: Date, deadline: Date) throws {
    guard now <= deadline else { throw SkillPolicyError.deadlineExceeded }
  }
}

public enum WasmtimeProbe {
  public static func libraryAvailable(at path: String, under root: String) -> Bool {
    path.withCString { pathPointer in
      root.withCString { rootPointer in
        synora_wasmtime_library_available(pathPointer, rootPointer)
      }
    }
  }

  public static func runStart(
    module: Data,
    library: String,
    under root: String,
    deadlineNanos: UInt64 = 0,
    cancelFlag: UnsafeMutablePointer<Int32>? = nil
  ) -> Bool {
    module.withUnsafeBytes { bytes in
      library.withCString { libraryPointer in
        root.withCString { rootPointer in
          synora_wasmtime_run_start(
            libraryPointer, rootPointer, bytes.bindMemory(to: UInt8.self).baseAddress,
            module.count, deadlineNanos, cancelFlag)
        }
      }
    }
  }
}
