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
      "Loaded"
    case .loading:
      "Loading"
    case .empty:
      "No records"
    case .error:
      "Unable to load records"
    case .offline:
      "Offline"
    case .conflict:
      "Sync conflict"
    }
  }

  var message: String {
    switch self {
    case .loaded:
      "Your local records are ready."
    case .loading:
      "Loading your local records."
    case .empty:
      "Your local records will appear here."
    case .error:
      "The local record index could not be loaded."
    case .offline:
      "The local library is available offline."
    case .conflict:
      "A local change needs review before it can be synced."
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
