import Foundation

@objc protocol AgentServiceProtocol {
  func run(_ request: Data, withReply reply: @escaping (Data) -> Void)
  func cancel(_ requestID: String, withReply reply: @escaping (Bool) -> Void)
}

final class SynoraAgentService: NSObject, NSXPCListenerDelegate, AgentServiceProtocol {
  private let lock = NSLock()
  private var cancelled = Set<String>()

  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
    -> Bool
  {
    connection.exportedInterface = NSXPCInterface(with: AgentServiceProtocol.self)
    connection.exportedObject = self
    connection.resume()
    return true
  }

  func run(_ request: Data, withReply reply: @escaping (Data) -> Void) {
    let result: SkillServiceResult
    do {
      let decoded = try JSONDecoder().decode(SkillServiceRequest.self, from: request)
      if isCancelled(decoded.requestID.uuidString) {
        result = SkillServiceResult(code: "cancelled", message: "request cancelled")
      } else if Date() > decoded.deadline {
        result = SkillServiceResult(code: "deadlineExceeded", message: "deadline exceeded")
      } else {
        result = SkillServiceResult(
          code: "runtimeUnavailable",
          message: "Wasmtime runtime is supplied by bootstrap_wasmtime.sh")
      }
    } catch {
      result = SkillServiceResult(code: "rejected", message: "invalid request")
    }
    reply((try? JSONEncoder().encode(result)) ?? Data())
  }

  func cancel(_ requestID: String, withReply reply: @escaping (Bool) -> Void) {
    lock.lock()
    cancelled.insert(requestID)
    lock.unlock()
    reply(true)
  }

  private func isCancelled(_ requestID: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled.contains(requestID)
  }
}

private struct SkillServiceRequest: Codable {
  let requestID: UUID
  let module: Data
  let deadline: Date
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
