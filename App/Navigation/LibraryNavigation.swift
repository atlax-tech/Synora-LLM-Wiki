import SwiftUI
import SynoraDesignSystem

struct LibraryNavigation: View {
  @Bindable var model: ShellModel

  var body: some View {
    VStack(spacing: 0) {
      SidebarBrandButton {
        model.selectSidebarItem(.today)
      }
      .padding(.horizontal, SynoraSpacing.xs)
      .padding(.top, SynoraSpacing.xs)

      sidebarList
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(minWidth: ShellLayoutPolicy.sidebarWidth, maxHeight: .infinity)
    .accessibilityLabel("Library navigation")
    .accessibilityValue(model.sidebarSelection?.title ?? "No selection")
    .accessibilityHint("Use arrow keys to navigate library sections")
    .accessibilityIdentifier(ShellAccessibilityID.sidebar)
    .focusSection()
  }

  private var sidebarList: some View {
    List(selection: selectionBinding) {
      sidebarSection(SidebarSections.home)
      sidebarSection(SidebarSections.knowledge)
      sidebarSection(SidebarSections.journal)
    }
    .listStyle(.sidebar)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private func sidebarSection(_ section: SidebarSection) -> some View {
    Section(section.title) {
      ForEach(section.items) { item in
        SidebarItemLabel(
          item: item,
          count: count(for: item)
        )
        .tag(item)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityHint(
          item.recordKind.map { "Shows \($0.title)" } ?? "Selects this library item"
        )
        .accessibilityIdentifier(ShellAccessibilityID.sidebarItem(item))
      }
    }
  }

  private var selectionBinding: Binding<SidebarItem?> {
    Binding(
      get: { model.sidebarSelection },
      set: { model.selectSidebarItem($0) }
    )
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

private struct SidebarBrandButton: View {
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: SynoraSpacing.sm) {
        Image("SynoraProductLogo")
          .resizable()
          .scaledToFit()
          .frame(width: 48, height: 48)
          .accessibilityHidden(true)

        Text("Wiki")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(SynoraSemanticColor.inkPrimary.color)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, SynoraSpacing.sm)
      .frame(minHeight: 56)
      .contentShape(.rect(cornerRadius: SynoraRadius.control))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Wiki")
    .accessibilityHint("Returns to Today")
    .accessibilityIdentifier(ShellAccessibilityID.sidebarBrand)
  }
}

private struct SidebarItemLabel: View {
  let item: SidebarItem
  let count: Int?

  var body: some View {
    Label {
      HStack(spacing: SynoraSpacing.xs) {
        Text(item.title)
          .lineLimit(1)

        Spacer(minLength: SynoraSpacing.xs)

        if let count {
          Text(count, format: .number)
            .font(SynoraTypography.metadata.font)
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(count) records")
        }
      }
    } icon: {
      Image(systemName: item.systemImage)
        .frame(width: 16)
    }
    .font(SynoraTypography.navigation.font)
    .foregroundStyle(.primary)
    .frame(minHeight: 33)
  }
}
