import SwiftUI
import SynoraDesignSystem

struct ShellRootView: View {
  @State private var model: ShellModel
  @SceneStorage("synora.shell.sidebar-visible") private var persistedSidebarVisible = true
  @SceneStorage("synora.shell.inspector-visible") private var persistedInspectorVisible = true

  init() {
    _model = State(initialValue: ShellModel())
  }

  var body: some View {
    GeometryReader { geometry in
      NavigationSplitView(columnVisibility: columnVisibilityBinding) {
        ShellSidebarPlaceholder()
          .navigationSplitViewColumnWidth(
            min: ShellLayoutPolicy.sidebarWidth,
            ideal: ShellLayoutPolicy.sidebarWidth,
            max: ShellLayoutPolicy.sidebarWidth
          )
      } content: {
        ShellRecordListPlaceholder()
          .navigationSplitViewColumnWidth(
            min: ShellLayoutPolicy.recordListWidth,
            ideal: ShellLayoutPolicy.recordListWidth,
            max: ShellLayoutPolicy.recordListWidth
          )
      } detail: {
        ShellEditorPlaceholder()
          .frame(minWidth: ShellLayoutPolicy.editorMinimumWidth)
      }
      .inspector(isPresented: inspectorBinding) {
        ShellInspectorPlaceholder()
          .inspectorColumnWidth(
            min: ShellLayoutPolicy.inspectorWidth,
            ideal: ShellLayoutPolicy.inspectorWidth,
            max: ShellLayoutPolicy.inspectorWidth
          )
      }
      .frame(minWidth: 1100, minHeight: 720)
      .onAppear {
        model.configure(
          desiredSidebarVisible: persistedSidebarVisible,
          desiredInspectorVisible: persistedInspectorVisible
        )
        model.reconcile(width: geometry.size.width)
      }
      .onChange(of: geometry.size.width) { _, width in
        model.reconcile(width: width)
      }
      .background(WindowMetricsReader { _ in })
    }
    .accessibilityIdentifier("shell-window")
  }

  private var columnVisibilityBinding: Binding<NavigationSplitViewVisibility> {
    Binding(
      get: {
        model.effectiveSidebarVisible ? .all : .doubleColumn
      },
      set: { visibility in
        let visible = visibility != .detailOnly
        model.setDesiredSidebarVisible(visible)
        persistedSidebarVisible = visible
      }
    )
  }

  private var inspectorBinding: Binding<Bool> {
    Binding(
      get: { model.effectiveInspectorVisible },
      set: { presented in
        model.setDesiredInspectorVisible(presented)
        persistedInspectorVisible = presented
      }
    )
  }
}

private struct ShellSidebarPlaceholder: View {
  var body: some View {
    VStack(alignment: .leading, spacing: SynoraSpacing.md) {
      Text("Library")
        .font(SynoraTypography.sectionLabel.font)
        .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
      Spacer()
    }
    .padding(SynoraSpacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(SynoraSemanticColor.sidebar.color)
    .accessibilityIdentifier("sidebar")
  }
}

private struct ShellRecordListPlaceholder: View {
  var body: some View {
    VStack(alignment: .leading, spacing: SynoraSpacing.md) {
      Text("Records")
        .font(SynoraTypography.sectionTitle.font)
        .foregroundStyle(SynoraSemanticColor.inkPrimary.color)
      Spacer()
    }
    .padding(SynoraSpacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(SynoraSemanticColor.list.color)
    .accessibilityIdentifier("record-list")
  }
}

private struct ShellEditorPlaceholder: View {
  var body: some View {
    VStack(alignment: .leading, spacing: SynoraSpacing.md) {
      Text("Select a record")
        .font(SynoraTypography.documentTitle.font)
        .foregroundStyle(SynoraSemanticColor.inkPrimary.color)
      Text("Your local records will appear here.")
        .font(SynoraTypography.body.font)
        .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
      Spacer()
    }
    .padding(SynoraSpacing.xxl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(SynoraSemanticColor.canvas.color)
    .accessibilityIdentifier("editor")
  }
}

private struct ShellInspectorPlaceholder: View {
  var body: some View {
    VStack(alignment: .leading, spacing: SynoraSpacing.md) {
      Text("Context")
        .font(SynoraTypography.sectionTitle.font)
        .foregroundStyle(SynoraSemanticColor.inkPrimary.color)
      Spacer()
    }
    .padding(SynoraSpacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(SynoraSemanticColor.inspector.color)
    .accessibilityIdentifier("inspector")
  }
}
