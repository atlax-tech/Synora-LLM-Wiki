import Foundation

struct Record: Equatable, Identifiable, Sendable {
  let id: UUID
  let kind: RecordKind
  let title: String
  let summary: String
  let modifiedAt: Date
  let thumbnailName: String?

  init(
    id: UUID,
    kind: RecordKind,
    title: String,
    summary: String,
    modifiedAt: Date,
    thumbnailName: String? = nil
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.summary = summary
    self.modifiedAt = modifiedAt
    self.thumbnailName = thumbnailName
  }
}

struct RecordMonth: Comparable, Equatable, Hashable, Sendable {
  let year: Int
  let month: Int

  static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.year, lhs.month) < (rhs.year, rhs.month)
  }

  var title: String {
    String(format: "%04d-%02d", year, month)
  }
}

struct RecordGroup: Equatable, Identifiable, Sendable {
  let month: RecordMonth
  let records: [Record]

  var id: RecordMonth { month }
}
