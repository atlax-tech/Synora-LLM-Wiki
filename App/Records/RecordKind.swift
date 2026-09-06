import Foundation

enum RecordKind: String, CaseIterable, Hashable, Sendable {
  case note
  case journal

  var title: String {
    switch self {
    case .note:
      "Notes"
    case .journal:
      "Journal"
    }
  }
}
