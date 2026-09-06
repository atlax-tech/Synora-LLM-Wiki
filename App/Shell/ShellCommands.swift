import SwiftUI
import SynoraDesignSystem

enum ShellFocusTarget: Hashable {
  case search
}

struct ShellActions {
  let toggleSidebar: () -> Void
  let focusSearch: () -> Void
  let toggleInspector: () -> Void
  let toggleCommandPalette: () -> Void
  let selectRecordKind: (RecordKind) -> Void
  let closeTransientLayer: () -> Void
  let inspectorToggleEnabled: Bool
}

private struct ShellActionsKey: FocusedValueKey {
  typealias Value = ShellActions
}

extension FocusedValues {
  var shellActions: ShellActions? {
    get { self[ShellActionsKey.self] }
    set { self[ShellActionsKey.self] = newValue }
  }
}

enum ShellCommand: CaseIterable, Identifiable {
  case toggleSidebar
  case focusSearch
  case toggleInspector
  case selectNotes
  case selectJournal

  var id: Self { self }

  var title: String {
    switch self {
    case .toggleSidebar:
      "Toggle Sidebar"
    case .focusSearch:
      "Focus Search"
    case .toggleInspector:
      "Toggle Inspector"
    case .selectNotes:
      "Show Notes"
    case .selectJournal:
      "Show Journal"
    }
  }

  var systemImage: String {
    switch self {
    case .toggleSidebar:
      "sidebar.left"
    case .focusSearch:
      "magnifyingglass"
    case .toggleInspector:
      "sidebar.right"
    case .selectNotes:
      "note.text"
    case .selectJournal:
      "book.closed"
    }
  }

  var shortcut: String {
    switch self {
    case .toggleSidebar:
      "⌘⇧S"
    case .focusSearch:
      "⌘F"
    case .toggleInspector:
      "⌥⌘I"
    case .selectNotes:
      "⌘1"
    case .selectJournal:
      "⌘2"
    }
  }
}

struct ShellCommands: Commands {
  @FocusedValue(\.shellActions) private var actions

  var body: some Commands {
    CommandMenu("Navigate") {
      Button("Toggle Sidebar") {
        actions?.toggleSidebar()
      }
      .keyboardShortcut("s", modifiers: [.command, .shift])
      .disabled(actions == nil)

      Button("Focus Search") {
        actions?.focusSearch()
      }
      .keyboardShortcut("f", modifiers: [.command])
      .disabled(actions == nil)

      Button("Toggle Inspector") {
        actions?.toggleInspector()
      }
      .keyboardShortcut("i", modifiers: [.command, .option])
      .disabled(actions?.inspectorToggleEnabled != true)

      Button("Command Palette") {
        actions?.toggleCommandPalette()
      }
      .keyboardShortcut("k", modifiers: [.command])
      .disabled(actions == nil)

      Divider()

      Button("Show Notes") {
        actions?.selectRecordKind(.note)
      }
      .keyboardShortcut("1", modifiers: [.command])
      .disabled(actions == nil)

      Button("Show Journal") {
        actions?.selectRecordKind(.journal)
      }
      .keyboardShortcut("2", modifiers: [.command])
      .disabled(actions == nil)
    }
  }
}

struct ShellCommandPalette: View {
  let actions: ShellActions

  var body: some View {
    GlassEffectContainer(spacing: SynoraSpacing.sm) {
      VStack(alignment: .leading, spacing: SynoraSpacing.xs) {
        Text("Command Palette")
          .font(SynoraTypography.sectionTitle.font)
          .foregroundStyle(SynoraSemanticColor.inkPrimary.color)
          .padding(.horizontal, SynoraSpacing.sm)
          .padding(.top, SynoraSpacing.sm)

        ForEach(ShellCommand.allCases) { command in
          commandButton(command)
        }
      }
      .padding(SynoraSpacing.xs)
      .frame(width: 360)
      .glassEffect(.regular, in: .rect(cornerRadius: SynoraRadius.floatingControl))
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("command-palette")
    }
  }

  @ViewBuilder
  private func commandButton(_ command: ShellCommand) -> some View {
    Button {
      perform(command)
    } label: {
      HStack(spacing: SynoraSpacing.sm) {
        Image(systemName: command.systemImage)
          .frame(width: 18)
        Text(command.title)
        Spacer()
        Text(command.shortcut)
          .font(SynoraTypography.metadata.font)
          .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
      }
      .padding(.horizontal, SynoraSpacing.sm)
      .frame(minHeight: 32)
      .contentShape(.rect(cornerRadius: SynoraRadius.control))
    }
    .buttonStyle(.plain)
    .disabled(command == .toggleInspector && !actions.inspectorToggleEnabled)
    .accessibilityLabel(command.title)
  }

  private func perform(_ command: ShellCommand) {
    switch command {
    case .toggleSidebar:
      actions.toggleSidebar()
    case .focusSearch:
      actions.focusSearch()
    case .toggleInspector:
      actions.toggleInspector()
    case .selectNotes:
      actions.selectRecordKind(.note)
    case .selectJournal:
      actions.selectRecordKind(.journal)
    }
    actions.closeTransientLayer()
  }
}
