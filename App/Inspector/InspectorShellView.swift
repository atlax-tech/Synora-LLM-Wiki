import SwiftUI
import SynoraDesignSystem

struct InspectorShellView: View {
  @Bindable var model: ShellModel

  var body: some View {
    VStack(spacing: 0) {
      Picker("Inspector", selection: modeBinding) {
        ForEach(InspectorMode.allCases, id: \.self) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(.horizontal, SynoraSpacing.md)
      .padding(.vertical, SynoraSpacing.sm)
      .accessibilityLabel("Inspector mode")
      .accessibilityIdentifier("inspector-mode")

      ScrollView {
        Group {
          switch model.inspectorMode {
          case .context:
            contextContent
          case .skills:
            skillsContent
          }
        }
        .padding(SynoraSpacing.md)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(SynoraSemanticColor.inspector.color)
    .accessibilityLabel("Inspector")
    .accessibilityIdentifier("inspector")
  }

  private var modeBinding: Binding<InspectorMode> {
    Binding(
      get: { model.inspectorMode },
      set: { model.setInspectorMode($0) }
    )
  }

  @ViewBuilder
  private var contextContent: some View {
    if let record = model.selectedRecord(for: model.selectedRecordKind) {
      VStack(alignment: .leading, spacing: SynoraSpacing.md) {
        inspectorCard {
          Text("Record context")
            .font(SynoraTypography.sectionTitle.font)
            .foregroundStyle(SynoraSemanticColor.inkPrimary.color)

          InspectorMetadataRow(label: "Title", value: record.title)
          InspectorMetadataRow(label: "Type", value: record.kind.title)
          InspectorMetadataRow(
            label: "Modified",
            value: record.modifiedAt.formatted(date: .abbreviated, time: .shortened)
          )
        }
      }
    } else {
      InspectorEmptyView(
        systemImage: "square.stack.3d.up",
        title: "No record selected",
        message: "Select a record to inspect its local context."
      )
    }
  }

  private var skillsContent: some View {
    VStack(alignment: .leading, spacing: SynoraSpacing.md) {
      inspectorCard {
        Text("AI Skills")
          .font(SynoraTypography.sectionTitle.font)
          .foregroundStyle(SynoraSemanticColor.inkPrimary.color)
        Text("P1 shows availability only. Installing and executing skills arrive in a later phase.")
          .font(SynoraTypography.body.font)
          .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
          .fixedSize(horizontal: false, vertical: true)
      }

      inspectorCard {
        Label("No skills installed", systemImage: "wand.and.stars")
          .font(SynoraTypography.body.font)
          .foregroundStyle(SynoraSemanticColor.inkPrimary.color)
        Text("The local skill catalog is ready for a future lifecycle implementation.")
          .font(SynoraTypography.metadata.font)
          .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func inspectorCard<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: SynoraSpacing.sm, content: content)
      .padding(SynoraSpacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.regularMaterial, in: .rect(cornerRadius: SynoraRadius.inspectorCard))
      .overlay {
        RoundedRectangle(cornerRadius: SynoraRadius.inspectorCard)
          .stroke(SynoraSemanticColor.borderSubtle.color, lineWidth: 1)
      }
  }
}

private struct InspectorMetadataRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: SynoraSpacing.sm) {
      Text(label)
        .font(SynoraTypography.metadata.font)
        .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
        .frame(width: 64, alignment: .leading)
      Text(value)
        .font(SynoraTypography.body.font)
        .foregroundStyle(SynoraSemanticColor.inkPrimary.color)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }
}

private struct InspectorEmptyView: View {
  let systemImage: String
  let title: String
  let message: String

  var body: some View {
    VStack(spacing: SynoraSpacing.sm) {
      Image(systemName: systemImage)
        .font(.title2)
        .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
      Text(title)
        .font(SynoraTypography.sectionTitle.font)
        .foregroundStyle(SynoraSemanticColor.inkPrimary.color)
      Text(message)
        .font(SynoraTypography.body.font)
        .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .padding(SynoraSpacing.lg)
    .accessibilityElement(children: .combine)
  }
}
