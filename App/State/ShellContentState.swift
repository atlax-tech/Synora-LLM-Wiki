import Foundation

enum ShellContentState: String, CaseIterable, Identifiable, Sendable {
  case loaded
  case loading
  case empty
  case error
  case offline
  case conflict

  var id: Self { self }

  var title: String {
    switch self {
    case .loaded:
      String(localized: "Loaded")
    case .loading:
      String(localized: "Loading")
    case .empty:
      String(localized: "No records")
    case .error:
      String(localized: "Unable to load records")
    case .offline:
      String(localized: "Offline")
    case .conflict:
      String(localized: "Sync conflict")
    }
  }

  var message: String {
    switch self {
    case .loaded:
      String(localized: "Your local records are ready.")
    case .loading:
      String(localized: "Loading your local records.")
    case .empty:
      String(localized: "Your local records will appear here.")
    case .error:
      String(localized: "The local record index could not be loaded.")
    case .offline:
      String(localized: "The local library is available offline.")
    case .conflict:
      String(localized: "A local change needs review before it can be synced.")
    }
  }

  var systemImage: String {
    switch self {
    case .loaded:
      "checkmark.circle"
    case .loading:
      "arrow.triangle.2.circlepath"
    case .empty:
      "tray"
    case .error:
      "exclamationmark.triangle"
    case .offline:
      "wifi.slash"
    case .conflict:
      "exclamationmark.arrow.triangle.2.circlepath"
    }
  }
}
