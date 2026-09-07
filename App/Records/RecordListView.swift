import AppKit
import SwiftUI
import SynoraDesignSystem

struct RecordListView: View {
  @Bindable var model: ShellModel

  var body: some View {
    VStack(spacing: 0) {
      Picker("Record kind", selection: selectedRecordKindBinding) {
        ForEach(RecordKind.allCases, id: \.self) { kind in
          Text(kind.title).tag(kind)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .controlSize(.regular)
      .padding(.horizontal, SynoraSpacing.md)
      .padding(.vertical, SynoraSpacing.sm)
      .accessibilityLabel("Record kind")
      .accessibilityValue(model.selectedRecordKind.title)
      .accessibilityHint("Switches between notes and journal records")
      .accessibilityIdentifier(ShellAccessibilityID.recordKind)

      content
    }
    .background(SynoraSemanticColor.list.color)
    .accessibilityLabel("Record list")
    .accessibilityValue(
      model.selectedRecord(for: model.selectedRecordKind)?.title ?? "No record selected"
    )
    .accessibilityHint("Use arrow keys to select a record")
    .accessibilityIdentifier(ShellAccessibilityID.recordList)
    .focusSection()
  }

  private var content: AnyView {
    switch model.contentState {
    case .loaded, .empty:
      if groups.isEmpty || model.contentState == .empty {
        return AnyView(RecordListEmptyView(query: model.searchQuery))
      } else {
        return AnyView(
          List(selection: selectionBinding) {
            ForEach(groups) { group in
              Section(group.month.title) {
                ForEach(group.records) { record in
                  RecordRow(record: record)
                    .tag(record.id)
                }
              }
            }
          }
          .listStyle(.inset)
          .scrollContentBackground(.hidden)
          .background(SynoraSemanticColor.list.color))
      }
    case .loading, .error, .offline, .conflict:
      return AnyView(
        ShellStateView(
          state: model.contentState,
          retry: model.canRetryContentLoad ? { model.retryContentLoad() } : nil
        ))
    }
  }

  private var groups: [RecordGroup] {
    RecordListProjection.filterAndGroup(
      records: model.records(for: model.selectedRecordKind),
      query: model.searchQuery
    )
  }

  private var selectedRecordKindBinding: Binding<RecordKind> {
    Binding(
      get: { model.selectedRecordKind },
      set: { model.selectRecordKind($0) }
    )
  }

  private var selectionBinding: Binding<UUID?> {
    Binding(
      get: { model.selectedRecordIDs[model.selectedRecordKind] ?? nil },
      set: { model.selectRecord($0, in: model.selectedRecordKind) }
    )
  }
}

private struct RecordRow: View {
  let record: Record

  var body: some View {
    HStack(spacing: SynoraSpacing.sm) {
      RecordThumbnail(name: record.thumbnailName, label: record.title)

      VStack(alignment: .leading, spacing: SynoraSpacing.xxs) {
        Text(record.title)
          .font(SynoraTypography.listTitle.font)
          .foregroundStyle(SynoraSemanticColor.inkPrimary.color)
          .lineLimit(1)

        Text(record.summary)
          .font(SynoraTypography.metadata.font)
          .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
          .lineLimit(2)

        Text(record.modifiedAt, style: .date)
          .font(SynoraTypography.metadata.font)
          .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
          .lineLimit(1)
      }

      Spacer(minLength: 0)
    }
    .frame(minHeight: 79)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(record.title)
    .accessibilityValue(record.summary)
    .accessibilityHint("Selects this record")
    .accessibilityIdentifier(ShellAccessibilityID.record(record.id))
  }
}

private struct RecordThumbnail: View {
  let name: String?
  let label: String

  var body: some View {
    Group {
      if let name, let image = NSImage(named: name) {
        Image(nsImage: image)
          .resizable()
          .scaledToFill()
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: SynoraRadius.selection)
            .fill(SynoraSemanticColor.accentSoft.color)
          Image(systemName: "photo")
            .foregroundStyle(SynoraSemanticColor.accentText.color)
        }
      }
    }
    .frame(width: 51, height: 51)
    .clipShape(.rect(cornerRadius: SynoraRadius.selection))
    .accessibilityLabel("Thumbnail for \(label)")
  }
}

private struct RecordListEmptyView: View {
  let query: String

  var body: some View {
    VStack(spacing: SynoraSpacing.sm) {
      Image(systemName: query.isEmpty ? "tray" : "magnifyingglass")
        .font(.title2)
        .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
      Text(query.isEmpty ? "No records" : "No matching records")
        .font(SynoraTypography.sectionTitle.font)
        .foregroundStyle(SynoraSemanticColor.inkPrimary.color)
      Text(
        query.isEmpty ? "Your local records will appear here." : "Try a different title or summary."
      )
      .font(SynoraTypography.body.font)
      .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
      .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(SynoraSpacing.xl)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("record-empty")
  }
}
