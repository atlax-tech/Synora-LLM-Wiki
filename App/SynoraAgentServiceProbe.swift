import Darwin
import Foundation
import SynoraSkillProbe

@objc protocol AgentServiceProtocol {
  func run(_ request: Data, withReply reply: @escaping (Data) -> Void)
  func cancel(_ requestID: String, withReply reply: @escaping (Bool) -> Void)
}

final class SynoraAgentService: NSObject, NSXPCListenerDelegate, AgentServiceProtocol {
  private static let maxRequestBytes = 16 * 1024 * 1024
  private let lock = NSLock()
  private var active = Set<String>()
  private var cancelled = Set<String>()

  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
    -> Bool
  {
    guard connection.effectiveUserIdentifier == getuid() else {
      return false
    }
    connection.exportedInterface = NSXPCInterface(with: AgentServiceProtocol.self)
    connection.exportedObject = self
    connection.invalidationHandler = {}
    connection.interruptionHandler = {}
    connection.resume()
    return true
  }

  func run(_ request: Data, withReply reply: @escaping (Data) -> Void) {
    guard request.count <= Self.maxRequestBytes else {
      reply(encode(SkillServiceResult(code: "rejected", message: "request too large")))
      return
    }

    let result: SkillServiceResult
    var responseLimit = Self.maxRequestBytes
    do {
      let decoded = try JSONDecoder().decode(SkillRequest.self, from: request)
      responseLimit = max(
        decoded.policy.maxResponseBytes, SkillPolicyEvaluator.minimumResponseBytes)
      if begin(decoded.requestID.uuidString) {
        defer { finish(decoded.requestID.uuidString) }
        do {
          try SkillPolicyEvaluator().validate(decoded, now: Date())
          if isCancelled(decoded.requestID.uuidString) {
            result = SkillServiceResult(code: "cancelled", message: "request cancelled")
          } else {
            result = SkillServiceResult(
              code: "runtimeUnavailable",
              message: "Wasmtime runtime is supplied by bootstrap_wasmtime.sh")
          }
        } catch let error as SkillPolicyError {
          result = serviceResult(for: error)
        }
      } else {
        result = SkillServiceResult(code: "cancelled", message: "request cancelled")
      }
    } catch {
      result = SkillServiceResult(code: "rejected", message: "invalid request")
    }
    let encoded = encode(result)
    if encoded.count <= responseLimit {
      reply(encoded)
    } else {
      reply(encode(SkillServiceResult(code: "responseTooLarge", message: "response too large")))
    }
  }

  func cancel(_ requestID: String, withReply reply: @escaping (Bool) -> Void) {
    lock.lock()
    let accepted = active.contains(requestID)
    if accepted {
      cancelled.insert(requestID)
    }
    lock.unlock()
    reply(accepted)
  }

  private func isCancelled(_ requestID: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled.contains(requestID)
  }

  private func begin(_ requestID: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard cancelled.remove(requestID) == nil else { return false }
    active.insert(requestID)
    return true
  }

  private func finish(_ requestID: String) {
    lock.lock()
    active.remove(requestID)
    cancelled.remove(requestID)
    lock.unlock()
  }

  private func serviceResult(for error: SkillPolicyError) -> SkillServiceResult {
    switch error {
    case .deadlineExceeded:
      return SkillServiceResult(code: "deadlineExceeded", message: "deadline exceeded")
    case .moduleTooLarge:
      return SkillServiceResult(code: "rejected", message: "module too large")
    case .invalidModule:
      return SkillServiceResult(code: "rejected", message: "invalid wasm module")
    case .invalidResponseLimit:
      return SkillServiceResult(code: "rejected", message: "invalid response limit")
    case .capabilityDenied, .networkDenied:
      return SkillServiceResult(code: "rejected", message: "capability denied")
    case .responseTooLarge:
      return SkillServiceResult(code: "responseTooLarge", message: "response too large")
    }
  }

  private func encode(_ result: SkillServiceResult) -> Data {
    (try? JSONEncoder().encode(result)) ?? Data()
  }
}

private struct SkillServiceResult: Codable {
  let code: String
  let message: String
}

@main
enum SynoraAgentServiceMain {
  static func main() {
    let listener = NSXPCListener.service()
    let delegate = SynoraAgentService()
    listener.delegate = delegate
    listener.resume()
    RunLoop.current.run()
  }
}
