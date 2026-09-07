import Foundation
import SynoraDomain

public protocol LinkPreviewTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: LinkPreviewTransport {}

public enum LinkPreviewFailure: String, Codable, Hashable, Sendable {
  case invalidURL
  case unsupportedScheme
  case requestFailed
  case invalidResponse
  case invalidHTML

  public var message: String {
    switch self {
    case .invalidURL: "The link URL is invalid"
    case .unsupportedScheme: "Only HTTP and HTTPS links have remote previews"
    case .requestFailed: "The link preview request failed"
    case .invalidResponse: "The link preview response was not usable"
    case .invalidHTML: "The page did not contain preview metadata"
    }
  }
}

public enum LinkPreviewState: Codable, Hashable, Sendable {
  case existing
  case fetched
  case networkDisabled
  case failed(LinkPreviewFailure)
}

public struct LinkPreviewResult: Codable, Hashable, Sendable {
  public let card: LinkCard
  public let state: LinkPreviewState

  public init(card: LinkCard, state: LinkPreviewState) {
    self.card = card
    self.state = state
  }

  public var message: String? {
    switch state {
    case .existing, .fetched: nil
    case .networkDisabled: "Network access is disabled; showing the saved link"
    case .failed(let failure): failure.message
    }
  }
}

public actor LinkPreviewLoader {
  private let transport: any LinkPreviewTransport
  private let maxResponseBytes: Int

  public init(
    transport: any LinkPreviewTransport = URLSession.shared,
    maxResponseBytes: Int = 1_000_000
  ) {
    self.transport = transport
    self.maxResponseBytes = max(maxResponseBytes, 1)
  }

  public func load(_ card: LinkCard, allowsNetwork: Bool) async -> LinkPreviewResult {
    guard card.isSupportedURL else {
      return LinkPreviewResult(card: card, state: .failed(.invalidURL))
    }
    guard allowsNetwork else {
      return LinkPreviewResult(card: card, state: .networkDisabled)
    }
    guard let url = URL(string: card.url), ["http", "https"].contains(url.scheme?.lowercased()) else {
      return LinkPreviewResult(card: card, state: .failed(.unsupportedScheme))
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 5
    request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await transport.data(for: request)
    } catch {
      return LinkPreviewResult(card: card, state: .failed(.requestFailed))
    }
    guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
      return LinkPreviewResult(card: card, state: .failed(.invalidResponse))
    }
    let metadata = Self.metadata(from: data.prefix(maxResponseBytes))
    guard metadata.title != nil || metadata.summary != nil else {
      return LinkPreviewResult(card: card, state: .failed(.invalidHTML))
    }
    return LinkPreviewResult(
      card: LinkCard(
        url: card.url,
        title: metadata.title ?? card.title,
        summary: metadata.summary ?? card.summary),
      state: .fetched)
  }

  private static func metadata(from data: Data.SubSequence) -> (title: String?, summary: String?) {
    let html = String(decoding: data, as: UTF8.self)
    let title = firstMatch(
      pattern: #"<title\b[^>]*>(.*?)</title>"#,
      in: html)
    var summary: String?
    let tags = matches(pattern: #"<meta\b[^>]*>"#, in: html)
    for tag in tags {
      let key = attribute(named: "name", in: tag) ?? attribute(named: "property", in: tag)
      guard let key, ["description", "og:description"].contains(key.lowercased()),
        let content = attribute(named: "content", in: tag)
      else { continue }
      summary = content
      break
    }
    return (clean(title), clean(summary))
  }

  private static func firstMatch(pattern: String, in value: String) -> String? {
    matches(pattern: pattern, in: value).first
  }

  private static func matches(pattern: String, in value: String) -> [String] {
    guard let regex = try? NSRegularExpression(
      pattern: pattern,
      options: [.caseInsensitive, .dotMatchesLineSeparators])
    else { return [] }
    let range = NSRange(value.startIndex..., in: value)
    return regex.matches(in: value, range: range).compactMap { match in
      let matchRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
      guard let range = Range(matchRange, in: value) else { return nil }
      return String(value[range])
    }
  }

  private static func attribute(named name: String, in tag: String) -> String? {
    let pattern = #"(?:^|\s)"# + NSRegularExpression.escapedPattern(for: name)
      + #"\s*=\s*["']([^"']*)["']"#
    return firstMatch(pattern: pattern, in: tag)
  }

  private static func clean(_ value: String?) -> String? {
    guard let value else { return nil }
    let decoded = value
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
    let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
