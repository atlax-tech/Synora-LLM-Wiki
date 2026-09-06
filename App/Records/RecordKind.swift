import Foundation

enum RecordKind: String, CaseIterable, Hashable, Sendable {
  case note
  case journal

  var title: String {
    switch self {
    case .note:
      String(localized: "Notes")
    case .journal:
      String(localized: "Journal")
    }
  }
}
