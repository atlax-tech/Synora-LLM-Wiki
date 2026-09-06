import AppKit
import SwiftUI
import SynoraDesignSystem

struct RecordEditorView: View {
  let model: ShellModel

  var body: some View {
    ScrollView {
      Group {
        if let record = model.selectedRecord(for: model.selectedRecordKind) {
          recordContent(record)
        } else {
          emptyContent
        }
      }
      .frame(maxWidth: 820, alignment: .leading)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, SynoraSpacing.xxl)
      .padding(.vertical, SynoraSpacing.xl)
    }
    .background(SynoraSemanticColor.canvas.color)
    .accessibilityLabel("Editor")
    .accessibilityValue(
      model.selectedRecord(for: model.selectedRecordKind)?.title ?? "No record selected"
    )
    .accessibilityHint("Read-only record preview")
    .accessibilityIdentifier(ShellAccessibilityID.editor)
    .focusSection()
  }

  private func recordContent(_ record: Record) -> some View {
    VStack(alignment: .leading, spacing: SynoraSpacing.lg) {
      Text(record.title)
        .font(SynoraTypography.documentTitle.font)
        .foregroundStyle(SynoraSemanticColor.inkPrimary.color)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: SynoraSpacing.sm) {
        Label(record.kind.title, systemImage: record.kind == .note ? "note.text" : "book.closed")
        Text(record.modifiedAt, style: .date)
      }
      .font(SynoraTypography.metadata.font)
      .foregroundStyle(SynoraSemanticColor.inkSecondary.color)

      Divider()

      Text(record.summary)
        .font(SynoraTypography.body.font)
        .foregroundStyle(SynoraSemanticColor.inkPrimary.color)
        .lineSpacing(SynoraTypography.body.size * (SynoraTypography.body.lineHeight - 1))
        .fixedSize(horizontal: false, vertical: true)

      if let thumbnailName = record.thumbnailName {
        RecordEditorImage(name: thumbnailName, label: record.title)
      }

      Text("Read-only fixture preview")
        .font(SynoraTypography.metadata.font)
        .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
    }
  }

  private var emptyContent: some View {
    VStack(alignment: .leading, spacing: SynoraSpacing.md) {
      Text("Select a record")
        .font(SynoraTypography.documentTitle.font)
        .foregroundStyle(SynoraSemanticColor.inkPrimary.color)
      Text("Your local records will appear here.")
        .font(SynoraTypography.body.font)
        .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
    }
  }
}

private struct RecordEditorImage: View {
  let name: String
  let label: String

  var body: some View {
    if let image = NSImage(named: name) {
      Image(nsImage: image)
        .resizable()
        .scaledToFit()
        .frame(maxWidth: 820, maxHeight: 320)
        .clipShape(.rect(cornerRadius: SynoraRadius.inspectorCard))
        .accessibilityLabel("Image for \(label)")
    }
  }
}
