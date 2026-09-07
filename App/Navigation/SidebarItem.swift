import Foundation

enum SidebarItem: String, CaseIterable, Hashable, Identifiable, Sendable {
  case today
  case inbox
  case allNotes
  case topics
  case tags
  case favorites
  case trash
  case allJournals
  case journalYears
  case travel
  case life
  case daily
  case ideas

  var id: Self { self }

  var title: String {
    switch self {
    case .today:
      String(localized: "Today")
    case .inbox:
      String(localized: "Inbox")
    case .allNotes:
      String(localized: "All Notes")
    case .topics:
      String(localized: "Topics")
    case .tags:
      String(localized: "Tags")
    case .favorites:
      String(localized: "Favorites")
    case .trash:
      String(localized: "Trash")
    case .allJournals:
      String(localized: "All Journal")
    case .journalYears:
      String(localized: "Years")
    case .travel:
      String(localized: "Travel")
    case .life:
      String(localized: "Life")
    case .daily:
      String(localized: "Daily")
    case .ideas:
      String(localized: "Ideas")
    }
  }

  var systemImage: String {
    switch self {
    case .today:
      "sun.max"
    case .inbox:
      "tray"
    case .allNotes:
      "note.text"
    case .topics:
      "square.grid.2x2"
    case .tags:
      "tag"
    case .favorites:
      "star"
    case .trash:
      "trash"
    case .allJournals:
      "book.closed"
    case .journalYears:
      "calendar"
    case .travel:
      "airplane"
    case .life:
      "heart"
    case .daily:
      "clock"
    case .ideas:
      "lightbulb"
    }
  }

  var recordKind: RecordKind? {
    switch self {
    case .allNotes, .topics, .tags, .favorites, .trash:
      .note
    case .allJournals, .journalYears, .travel, .life, .daily, .ideas:
      .journal
    case .today, .inbox:
      nil
    }
  }
}

struct SidebarSection: Equatable, Sendable {
  let title: String
  let items: [SidebarItem]
}

enum SidebarSections {
  static let home = SidebarSection(
    title: String(localized: "Home"),
    items: [.today, .inbox]
  )
  static let knowledge = SidebarSection(
    title: String(localized: "Knowledge"),
    items: [.allNotes, .topics, .tags, .favorites, .trash]
  )
  static let journal = SidebarSection(
    title: String(localized: "Journal"),
    items: [.allJournals, .journalYears, .travel, .life, .daily, .ideas]
  )
  static let all: [SidebarSection] = [home, knowledge, journal]
}
