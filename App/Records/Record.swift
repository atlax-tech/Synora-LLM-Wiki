import Foundation
import SynoraDomain

struct Record: Equatable, Identifiable, Sendable {
  let id: UUID
  let kind: RecordKind
  let title: String
  let summary: String
  let modifiedAt: Date
  let thumbnailName: String?
  let revision: Int
  let journalDate: Date?
  let metadata: [String: String]

  init(
    id: UUID,
    kind: RecordKind,
    title: String,
    summary: String,
    modifiedAt: Date,
    thumbnailName: String? = nil,
    revision: Int = 0,
    journalDate: Date? = nil,
    metadata: [String: String] = [:]
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.summary = summary
    self.modifiedAt = modifiedAt
    self.thumbnailName = thumbnailName
    self.revision = revision
    self.journalDate = journalDate
    self.metadata = metadata
  }

  init(domain: SynoraDomain.Record, summary: String = "", thumbnailName: String? = nil) {
    let modifiedAt = domain.metadata["modifiedAt"].flatMap(Double.init)
      .map { Date(timeIntervalSince1970: $0) }
      ?? domain.journalDate ?? Date()
    self.init(
      id: domain.id,
      kind: domain.kind == .journal ? .journal : .note,
      title: domain.title,
      summary: summary,
      modifiedAt: modifiedAt,
      thumbnailName: thumbnailName,
      revision: domain.revision,
      journalDate: domain.journalDate,
      metadata: domain.metadata
    )
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
