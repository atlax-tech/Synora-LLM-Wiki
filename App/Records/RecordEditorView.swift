import AppKit
import SwiftUI
import SynoraAssets
import SynoraDesignSystem
import SynoraDomain
import SynoraEditorKit
import UniformTypeIdentifiers

struct RecordEditorView: View {
  @Bindable var model: ShellModel
  @State private var importingAttachment = false
  @State private var replacingAttachment = false
  @State private var replacementTarget: AttachmentReplacement?

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
    .accessibilityHint("Edit the selected record")
    .accessibilityIdentifier(ShellAccessibilityID.editor)
    .focusSection()
  }

  private func recordContent(_ record: Record) -> some View {
    VStack(alignment: .leading, spacing: SynoraSpacing.lg) {
      TextField("Title", text: titleBinding(for: record))
        .font(SynoraTypography.documentTitle.font)
        .foregroundStyle(SynoraSemanticColor.inkPrimary.color)
        .textFieldStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Record title")
        .accessibilityIdentifier("editor-title")

      HStack(spacing: SynoraSpacing.sm) {
        Label(record.kind.title, systemImage: record.kind == .note ? "note.text" : "book.closed")
        Text(record.modifiedAt, style: .date)
        Spacer(minLength: 0)
        Text(model.editorSaveState.title)
          .accessibilityLabel("Save status")
          .accessibilityValue(model.editorSaveState.title)
      }
      .font(SynoraTypography.metadata.font)
      .foregroundStyle(SynoraSemanticColor.inkSecondary.color)

      Divider()

      SynoraEditorRepresentable(
        text: model.editorText(for: record),
        onTextChange: { model.setEditorText($0, for: record) }
      )
      .frame(minHeight: 260)
      .background(SynoraSemanticColor.canvas.color)
      .overlay {
        RoundedRectangle(cornerRadius: SynoraRadius.control)
          .stroke(SynoraSemanticColor.borderSubtle.color, lineWidth: 1)
      }
      .clipShape(.rect(cornerRadius: SynoraRadius.control))
      .accessibilityLabel("Record body")
      .accessibilityIdentifier("editor-body")
      .onDisappear { model.saveEditorNow(for: record) }

      HStack {
        if model.attachmentImportEnabled {
          Button("Add attachment", systemImage: "paperclip") {
            importingAttachment = true
          }
          .accessibilityIdentifier("editor-add-attachment")
        }
        Spacer(minLength: 0)
      }

      if let assetStore = model.assetStore {
        let blocks = model.mediaBlocks(for: record)
        if !blocks.isEmpty {
          RecordMediaStack(
            blocks: blocks,
            assets: model.mediaAssets(for: record),
            assetStore: assetStore,
            onReplace: { blockID, assetID in
              replacementTarget = AttachmentReplacement(blockID: blockID, assetID: assetID)
              replacingAttachment = true
            },
            onRemove: { blockID, assetID in
              model.removeAttachment(assetID: assetID, from: blockID, for: record)
            })
        }
      }

      if let thumbnailName = record.thumbnailName {
        RecordEditorImage(name: thumbnailName, label: record.title)
      }
    }
    .fileImporter(
      isPresented: $importingAttachment,
      allowedContentTypes: [.item],
      allowsMultipleSelection: false
    ) { result in
      if case .success(let urls) = result, let url = urls.first {
        model.importAttachment(from: url, for: record)
      }
    }
    .fileImporter(
      isPresented: $replacingAttachment,
      allowedContentTypes: [.item],
      allowsMultipleSelection: false
    ) { result in
      guard let target = replacementTarget else { return }
      replacementTarget = nil
      replacingAttachment = false
      if case .success(let urls) = result, let url = urls.first {
        model.replaceAttachment(
          from: url,
          assetID: target.assetID,
          in: target.blockID,
          for: record)
      }
    }
  }

  private func titleBinding(for record: Record) -> Binding<String> {
    Binding(
      get: { model.editorTitle(for: record) },
      set: { model.setEditorTitle($0, for: record) }
    )
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

private struct AttachmentReplacement: Equatable {
  let blockID: UUID
  let assetID: UUID
}

private struct SynoraEditorRepresentable: NSViewRepresentable {
  let text: String
  let onTextChange: @MainActor (String) -> Void

  @MainActor
  func makeNSView(context: Context) -> SynoraTextView {
    let view = SynoraTextView()
    view.string = text
    view.onTextChange = onTextChange
    return view
  }

  @MainActor
  func updateNSView(_ nsView: SynoraTextView, context: Context) {
    if nsView.string != text { nsView.setDocumentText(text) }
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

private struct RecordMediaStack: View {
  let blocks: [Block]
  let assets: [UUID: Asset]
  let assetStore: AssetStore
  let onReplace: (UUID, UUID) -> Void
  let onRemove: (UUID, UUID) -> Void

  @State private var previews: [UUID: AssetPreview] = [:]
  @State private var failures: [UUID: MediaPreviewFailure] = [:]

  var body: some View {
    LazyVStack(alignment: .leading, spacing: SynoraSpacing.md) {
      ForEach(blocks, id: \.id) { block in
        mediaBlock(block)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Media blocks")
  }

  @ViewBuilder
  private func mediaBlock(_ block: Block) -> some View {
    switch block.content {
    case .assets(let placements)?:
      ForEach(placements, id: \.assetID) { placement in
        if let asset = assets[placement.assetID] {
          mediaAsset(asset, placement: placement, block: block)
        }
      }
    case .link(let card)?:
      VStack(alignment: .leading, spacing: SynoraSpacing.xs) {
        Label(block.type.accessibilityName, systemImage: "link")
          .font(SynoraTypography.metadata.font)
          .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
        Text(card.title ?? card.url)
          .font(SynoraTypography.sectionTitle.font)
          .foregroundStyle(SynoraSemanticColor.inkPrimary.color)
        if let summary = card.summary, !summary.isEmpty {
          Text(summary)
            .font(SynoraTypography.body.font)
            .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
        }
        Text(card.url)
          .font(SynoraTypography.metadata.font)
          .foregroundStyle(SynoraSemanticColor.accentText.color)
      }
      .padding(SynoraSpacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(SynoraSemanticColor.list.color)
      .clipShape(.rect(cornerRadius: SynoraRadius.control))
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Link: \(card.title ?? card.url)")
      .accessibilityValue("Editable")
    default:
      EmptyView()
    }
  }

  @ViewBuilder
  private func mediaAsset(
    _ asset: Asset,
    placement: AssetPlacement,
    block: Block
  ) -> some View {
    VStack(alignment: .leading, spacing: SynoraSpacing.xs) {
      switch failures[asset.id] {
      case .some(let failure):
        Label(failure.message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
      case nil:
        if let preview = previews[asset.id] {
          previewContent(preview, asset: asset)
        } else {
          Label(asset.originalFilename ?? "Attachment", systemImage: "paperclip")
            .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
        }
      }
      if !placement.caption.isEmpty {
        Text(placement.caption)
          .font(SynoraTypography.metadata.font)
          .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
      }
      HStack(spacing: SynoraSpacing.sm) {
        Button("Replace", systemImage: "arrow.triangle.2.circlepath") {
          onReplace(block.id, asset.id)
        }
        .accessibilityIdentifier("replace-attachment-\(asset.id.uuidString)")
        Button("Remove", systemImage: "trash") {
          onRemove(block.id, asset.id)
        }
        .accessibilityIdentifier("remove-attachment-\(asset.id.uuidString)")
      }
      .font(SynoraTypography.metadata.font)
    }
    .padding(SynoraSpacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(SynoraSemanticColor.list.color)
    .clipShape(.rect(cornerRadius: SynoraRadius.control))
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(block.type.accessibilityName): \(asset.originalFilename ?? "Attachment")")
    .accessibilityValue(placement.caption.isEmpty ? "Editable" : "Editable, \(placement.caption)")
    .task(id: asset.id) {
      let coordinator = MediaPreviewCoordinator(store: assetStore)
      let request = MediaPreviewRequest(
        blockID: block.id,
        blockRevision: block.revision,
        asset: asset)
      guard let result = await coordinator.load(request) else { return }
      switch result.state {
      case .ready(let preview): previews[result.assetID] = preview
      case .failed(let failure): failures[result.assetID] = failure
      }
    }
  }

  @ViewBuilder
  private func previewContent(_ preview: AssetPreview, asset: Asset) -> some View {
    switch preview.kind {
    case .image, .pdf, .file:
      if let url = preview.thumbnailURL, let image = NSImage(contentsOf: url) {
        Image(nsImage: image)
          .resizable()
          .scaledToFit()
          .frame(maxHeight: 280)
      } else if preview.kind == .pdf, let document = try? assetStore.pdfDocument(for: asset) {
        PDFDocumentView(document: document)
          .frame(height: 280)
      } else if preview.kind == .file, let item = try? assetStore.quickLookItem(for: asset) {
        QuickLookPreviewView(item: item)
          .frame(height: 220)
      } else {
        Label(asset.originalFilename ?? "Attachment", systemImage: "doc")
      }
    case .video, .audio:
      if let player = try? assetStore.player(for: asset) {
        LocalMediaPlayerView(player: player)
          .frame(height: preview.kind == .audio ? 72 : 220)
      } else {
        Label(asset.originalFilename ?? "Attachment", systemImage: preview.kind == .audio ? "waveform" : "film")
      }
    }
  }
}
