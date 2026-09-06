import Foundation

enum RecordFixtureCatalog {
  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }()

  private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
  }

  static let notes: [Record] = [
    Record(
      id: UUID(uuidString: "E4A7E4D7-4E30-4C05-9A3F-6C40D5C4A001")!,
      kind: .note,
      title: "Designing a calm workspace",
      summary: "Small constraints make a long-lived knowledge space easier to return to.",
      modifiedAt: date(2026, 9, 5),
      thumbnailName: "morning-run"
    ),
    Record(
      id: UUID(uuidString: "E4A7E4D7-4E30-4C05-9A3F-6C40D5C4A002")!,
      kind: .note,
      title: "Local-first search notes",
      summary: "Keep the first result useful even when the network is unavailable.",
      modifiedAt: date(2026, 8, 22),
      thumbnailName: "coffee"
    ),
    Record(
      id: UUID(uuidString: "E4A7E4D7-4E30-4C05-9A3F-6C40D5C4A003")!,
      kind: .note,
      title: "A tiny typography inventory",
      summary: "Use system roles so the content remains legible at larger sizes.",
      modifiedAt: date(2026, 8, 22)
    ),
  ]

  static let journals: [Record] = [
    Record(
      id: UUID(uuidString: "E4A7E4D7-4E30-4C05-9A3F-6C40D5C4B001")!,
      kind: .journal,
      title: "A slow morning in Kyoto",
      summary: "A walk, a warm cup of coffee, and one page written without rushing.",
      modifiedAt: date(2026, 9, 4),
      thumbnailName: "kyoto-street"
    ),
    Record(
      id: UUID(uuidString: "E4A7E4D7-4E30-4C05-9A3F-6C40D5C4B002")!,
      kind: .journal,
      title: "Notes from the alpine lake",
      summary: "Cold air, quiet water, and a reminder to leave room for the unexpected.",
      modifiedAt: date(2026, 7, 11),
      thumbnailName: "alpine-lake"
    ),
  ]

  static func records(for kind: RecordKind) -> [Record] {
    switch kind {
    case .note:
      notes
    case .journal:
      journals
    }
  }
}
