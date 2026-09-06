import SwiftUI
import SynoraDesignSystem

struct LibraryNavigation: View {
  @Bindable var model: ShellModel

  var body: some View {
    List(selection: selectionBinding) {
      ForEach(SidebarSections.all, id: \.title) { section in
        Section(section.title) {
          ForEach(section.items) { item in
            sidebarRow(item)
          }
        }
      }
    }
    .listStyle(.sidebar)
    .frame(minWidth: ShellLayoutPolicy.sidebarWidth)
    .accessibilityLabel("Library navigation")
    .accessibilityIdentifier("sidebar")
  }

  private var selectionBinding: Binding<SidebarItem?> {
    Binding(
      get: { model.sidebarSelection },
      set: { model.selectSidebarItem($0) }
    )
  }

  @ViewBuilder
  private func sidebarRow(_ item: SidebarItem) -> some View {
    HStack(spacing: SynoraSpacing.sm) {
      Image(systemName: item.systemImage)
        .frame(width: 16)
        .foregroundStyle(.secondary)

      Text(item.title)
        .font(SynoraTypography.navigation.font)
        .lineLimit(1)

      Spacer(minLength: SynoraSpacing.xs)

      if let count = count(for: item) {
        Text(count, format: .number)
          .font(SynoraTypography.metadata.font)
          .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
          .accessibilityLabel("\(count) records")
      }
    }
    .frame(minHeight: 33)
    .contentShape(.rect)
    .tag(item)
    .accessibilityIdentifier("sidebar-\(item.rawValue)")
  }

  private func count(for item: SidebarItem) -> Int? {
    switch item {
    case .allNotes:
      model.noteCount
    case .allJournals:
      model.journalCount
    default:
      nil
    }
  }
}
