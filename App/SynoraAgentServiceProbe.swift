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
  private var cancelFlags: [String: CancellationToken] = [:]

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
      let token = CancellationToken()
      if begin(decoded.requestID.uuidString, token: token) {
        defer { finish(decoded.requestID.uuidString) }
        do {
          try SkillPolicyEvaluator().validate(decoded, now: Date())
          if isCancelled(decoded.requestID.uuidString) {
            result = SkillServiceResult(code: "cancelled", message: "request cancelled")
          } else if runGuest(decoded) {
            result = SkillServiceResult(code: "success", message: "guest start completed")
          } else if isCancelled(decoded.requestID.uuidString) {
            result = SkillServiceResult(code: "cancelled", message: "request cancelled")
          } else {
            result = SkillServiceResult(
              code: "runtimeFailure",
              message: "guest execution failed")
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
      if let flag = cancelFlags[requestID] {
        WasmtimeProbe.setCancelFlag(flag.pointer)
      }
    }
    lock.unlock()
    reply(accepted)
  }

  private func isCancelled(_ requestID: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled.contains(requestID)
  }

  private func begin(_ requestID: String, token: CancellationToken) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard cancelled.remove(requestID) == nil else { return false }
    active.insert(requestID)
    cancelFlags[requestID] = token
    return true
  }

  private func finish(_ requestID: String) {
    lock.lock()
    active.remove(requestID)
    cancelled.remove(requestID)
    cancelFlags.removeValue(forKey: requestID)
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

  private func runGuest(_ request: SkillRequest) -> Bool {
    lock.lock()
    let flag = cancelFlags[request.requestID.uuidString]?.pointer
    lock.unlock()
    guard let frameworks = Bundle.main.privateFrameworksURL else { return false }
    let library = frameworks.appendingPathComponent("libwasmtime.dylib")
    let deadline = max(0, request.deadline.timeIntervalSinceNow)
    let broker = HostCapabilityBroker(
      requestID: request.requestID, policy: request.policy, deadline: request.deadline)
    return WasmtimeProbe.runStart(
      module: request.module,
      library: library.path,
      under: frameworks.path,
      deadlineNanos: UInt64(deadline * 1_000_000_000),
      cancelFlag: flag,
      broker: broker.request)
  }
}

private final class CancellationToken: @unchecked Sendable {
  let pointer: UnsafeMutablePointer<Int32>

  init() {
    pointer = .allocate(capacity: 1)
    pointer.initialize(to: 0)
  }

  deinit {
    pointer.deinitialize(count: 1)
    pointer.deallocate()
  }
}

private final class HostCapabilityBroker: @unchecked Sendable {
  private let root: URL
  private let policy: CapabilityPolicy
  private let deadline: Date
  private let evaluator = SkillPolicyEvaluator()

  init(requestID: UUID, policy: CapabilityPolicy, deadline: Date) {
    root = SkillPathPolicy.temporaryRoot(
      for: requestID, inside: FileManager.default.temporaryDirectory)
    self.policy = policy
    self.deadline = deadline
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func request(capability: String, target: String) -> Int32 {
    guard let capability = SkillCapability(rawValue: capability) else { return 1 }
    do {
      try evaluator.authorize(
        capability: capability, policy: policy, now: Date(), deadline: deadline)
      switch capability {
      case .readTemporaryDirectory:
        guard let directory = SkillPathPolicy.resolveTemporaryRead(target, root: root) else {
          return 1
        }
        _ = try FileManager.default.contentsOfDirectory(
          at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])
        return 0
      case .networkLoopback:
        try evaluator.authorizeNetwork(host: target, policy: policy)
        guard SkillPathPolicy.allowsLoopbackHost(target) else { return 1 }
        return LoopbackHTTPProbe.roundTrip(maxResponseBytes: policy.maxResponseBytes) ? 0 : 1
      case .writeProposal:
        return 1
      }
    } catch {
      return 1
    }
  }
}

private enum LoopbackHTTPProbe {
  static func roundTrip(maxResponseBytes: Int) -> Bool {
    guard maxResponseBytes >= 1 else { return false }
    let server = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard server >= 0 else { return false }
    defer { Darwin.close(server) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(server, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bound == 0, Darwin.listen(server, 1) == 0 else { return false }
    var actual = sockaddr_in()
    var actualLength = socklen_t(MemoryLayout<sockaddr_in>.size)
    let named = withUnsafeMutablePointer(to: &actual) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.getsockname(server, $0, &actualLength)
      }
    }
    guard named == 0 else { return false }
    let port = UInt16(bigEndian: actual.sin_port)

    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global(qos: .utility).async {
      defer { group.leave() }
      let client = Darwin.accept(server, nil, nil)
      guard client >= 0 else { return }
      defer { Darwin.close(client) }
      var request = [UInt8](repeating: 0, count: 512)
      _ = request.withUnsafeMutableBytes { Darwin.read(client, $0.baseAddress, $0.count) }
      let body = Data("synora-loopback".utf8)
      let response =
        Data(
          "HTTP/1.1 200 OK\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8
        ) + body
      _ = response.withUnsafeBytes { Darwin.write(client, $0.baseAddress, $0.count) }
    }

    let client = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard client >= 0 else { return false }
    defer { Darwin.close(client) }
    var destination = sockaddr_in()
    destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    destination.sin_family = sa_family_t(AF_INET)
    destination.sin_port = port.bigEndian
    destination.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let connected = withUnsafePointer(to: &destination) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard connected == 0 else { return false }
    let request = Data("GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n".utf8)
    _ = request.withUnsafeBytes { Darwin.write(client, $0.baseAddress, $0.count) }
    var response = Data()
    var buffer = [UInt8](repeating: 0, count: min(maxResponseBytes + 1024, 64 * 1024))
    while response.count <= maxResponseBytes + 1024 {
      let readCount = buffer.withUnsafeMutableBytes {
        Darwin.read(client, $0.baseAddress, $0.count)
      }
      guard readCount > 0 else { break }
      response.append(contentsOf: buffer.prefix(readCount))
    }
    let completed = group.wait(timeout: .now() + 1) == .success
    return completed && response.count <= maxResponseBytes + 1024
      && response.range(of: Data("synora-loopback".utf8)) != nil
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
