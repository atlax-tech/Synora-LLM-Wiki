import Foundation

enum ShellEnvironment {
  #if DEBUG
    private static let values = ProcessInfo.processInfo.environment
  #else
    private static let values: [String: String] = [:]
  #endif

  static var isUITesting: Bool {
    values["SYNORA_UI_TESTING"] == "1"
  }

  static var fixture: String? {
    values["SYNORA_FIXTURE"]
  }

  static var shellState: String? {
    guard let value = values["SYNORA_SHELL_STATE"], !value.isEmpty else { return nil }
    return value
  }

  static var contentSize: String? {
    values["SYNORA_CONTENT_SIZE"]
  }

  static var animationsDisabled: Bool {
    values["SYNORA_DISABLE_ANIMATIONS"] == "1"
  }
}
