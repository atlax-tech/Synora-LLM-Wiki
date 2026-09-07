import CoreGraphics
import Foundation

enum ShellEnvironment {
  #if DEBUG
    private static let values = ProcessInfo.processInfo.environment
  #else
    private static let values: [String: String] = [:]
  #endif

  #if DEBUG
    private static func value(for key: String) -> String? {
      if let environmentValue = values[key], !environmentValue.isEmpty {
        return environmentValue
      }

      let equalsPrefixes = ["--\(key)=", "-\(key)="]
      if let argument = CommandLine.arguments.first(where: { argument in
        equalsPrefixes.contains { argument.hasPrefix($0) }
      }), let prefix = equalsPrefixes.first(where: { argument.hasPrefix($0) }) {
        return String(argument.dropFirst(prefix.count))
      }

      if let argumentIndex = CommandLine.arguments.firstIndex(of: "-\(key)"),
        argumentIndex + 1 < CommandLine.arguments.count
      {
        return CommandLine.arguments[argumentIndex + 1]
      }

      return UserDefaults.standard.string(forKey: key)
    }
  #else
    private static func value(for key: String) -> String? { nil }
  #endif

  static var isUITesting: Bool {
    value(for: "SYNORA_UI_TESTING") == "1"
  }

  static var fixture: String? {
    value(for: "SYNORA_FIXTURE")
  }

  static var libraryPath: String {
    if let configured = value(for: "SYNORA_LIBRARY_PATH"), !configured.isEmpty {
      return configured
    }
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first ?? FileManager.default.temporaryDirectory
    return support.appendingPathComponent("SynoraWiki/library.sqlite").path
  }

  static var assetPath: String {
    if let configured = value(for: "SYNORA_ASSET_PATH"), !configured.isEmpty {
      return configured
    }
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first ?? FileManager.default.temporaryDirectory
    return support.appendingPathComponent("SynoraWiki/assets", isDirectory: true).path
  }

  static var shellState: String? {
    value(for: "SYNORA_SHELL_STATE")
  }

  static var contentSize: String? {
    value(for: "SYNORA_CONTENT_SIZE")
  }

  static var animationsDisabled: Bool {
    value(for: "SYNORA_DISABLE_ANIMATIONS") == "1"
  }

  static var forcedDarkMode: Bool? {
    switch value(for: "SYNORA_THEME")?.lowercased() {
    case "dark": true
    case "light": false
    default: nil
    }
  }

  static var requestedContentSize: CGSize? {
    guard let rawValue = value(for: "SYNORA_CONTENT_SIZE") else { return nil }
    let components = rawValue.split(separator: "x", maxSplits: 1).compactMap { Double($0) }
    guard components.count == 2 else { return nil }
    let size = CGSize(width: components[0], height: components[1])
    guard size.width >= 1, size.height >= 1 else { return nil }
    return size
  }
}
