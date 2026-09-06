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
  case context
  case skills

  var id: Self { self }

  var title: String {
    switch self {
    case .today:
      "Today"
    case .inbox:
      "Inbox"
    case .allNotes:
      "All Notes"
    case .topics:
      "Topics"
    case .tags:
      "Tags"
    case .favorites:
      "Favorites"
    case .trash:
      "Trash"
    case .allJournals:
      "All Journal"
    case .journalYears:
      "Years"
    case .travel:
      "Travel"
    case .life:
      "Life"
    case .daily:
      "Daily"
    case .ideas:
      "Ideas"
    case .context:
      "Context"
    case .skills:
      "AI Skills"
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
    case .context:
      "square.stack.3d.up"
    case .skills:
      "wand.and.stars"
    }
  }

  var recordKind: RecordKind? {
    switch self {
    case .allNotes, .topics, .tags, .favorites, .trash:
      .note
    case .allJournals, .journalYears, .travel, .life, .daily, .ideas:
      .journal
    case .today, .inbox, .context, .skills:
      nil
    }
  }
}

struct SidebarSection: Equatable, Sendable {
  let title: String
  let items: [SidebarItem]
}

enum SidebarSections {
  static let all: [SidebarSection] = [
    SidebarSection(title: "Home", items: [.today, .inbox]),
    SidebarSection(
      title: "Knowledge",
      items: [.allNotes, .topics, .tags, .favorites, .trash]
    ),
    SidebarSection(
      title: "Journal",
      items: [.allJournals, .journalYears, .travel, .life, .daily, .ideas]
    ),
    SidebarSection(title: "Tools", items: [.context, .skills]),
  ]
}
