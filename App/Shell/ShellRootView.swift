import SwiftUI
import SynoraDesignSystem

struct ShellRootView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var model: ShellModel
  @SceneStorage("synora.shell.sidebar-visible") private var persistedSidebarVisible = true
  @SceneStorage("synora.shell.inspector-visible") private var persistedInspectorVisible = true
  @State private var searchText = ""
  @State private var searchPresented = false

  init() {
    _model = State(initialValue: ShellModel())
  }

  var body: some View {
    ZStack(alignment: .topTrailing) {
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
        .searchable(
          text: $searchText,
          isPresented: $searchPresented,
          placement: .toolbar,
          prompt: "Search records"
        )
        .toolbar {
          ToolbarSpacer(.flexible)

          ToolbarItemGroup(placement: .primaryAction) {
            Button {
              model.toggleInspector()
            } label: {
              Label("Toggle Inspector", systemImage: "sidebar.right")
            }
            .disabled(!model.inspectorToggleEnabled)
            .help("Toggle Inspector (⌥⌘I)")
            .accessibilityIdentifier("toggle-inspector")

            Button {
              model.toggleCommandPalette()
            } label: {
              Label("Command Palette", systemImage: "command")
            }
            .help("Command Palette (⌘K)")
            .accessibilityIdentifier("command-palette-button")
          }
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

      if model.commandPalettePresented {
        ShellCommandPalette(actions: actions)
          .padding(.top, 56)
          .padding(.trailing, SynoraSpacing.lg)
          .transition(.opacity)
          .zIndex(1)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      ShellStatusBar(
        selectedRecordKind: model.selectedRecordKind,
        hasSelection: false,
        isInspectorSpaceLimited: !model.inspectorToggleEnabled
      )
    }
    .animation(
      .easeInOut(duration: SynoraMotion.inspector.duration(reducingMotion: reduceMotion)),
      value: model.commandPalettePresented
    )
    .onExitCommand {
      if model.commandPalettePresented {
        model.setCommandPalettePresented(false)
      }
    }
    .focusedSceneValue(\.shellActions, actions)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("window")
  }

  private var actions: ShellActions {
    ShellActions(
      toggleSidebar: { model.toggleSidebar() },
      focusSearch: { searchPresented = true },
      toggleInspector: { model.toggleInspector() },
      toggleCommandPalette: { model.toggleCommandPalette() },
      selectRecordKind: { model.selectRecordKind($0) },
      closeTransientLayer: { model.setCommandPalettePresented(false) },
      inspectorToggleEnabled: model.inspectorToggleEnabled
    )
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

private struct ShellStatusBar: View {
  let selectedRecordKind: RecordKind
  let hasSelection: Bool
  let isInspectorSpaceLimited: Bool

  var body: some View {
    HStack(spacing: SynoraSpacing.sm) {
      Image(systemName: hasSelection ? "checkmark.circle" : "circle.dashed")
        .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
      Text(hasSelection ? "Selected \(selectedRecordKind.title)" : "No record selected")
        .font(SynoraTypography.metadata.font)
        .foregroundStyle(SynoraSemanticColor.inkSecondary.color)

      Spacer()

      if isInspectorSpaceLimited {
        Label("Inspector unavailable at this width", systemImage: "rectangle.compress.vertical")
          .font(SynoraTypography.metadata.font)
          .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
      } else {
        Label("Local library", systemImage: "internaldrive")
          .font(SynoraTypography.metadata.font)
          .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
      }
    }
    .padding(.horizontal, SynoraSpacing.md)
    .frame(height: 32)
    .background(.regularMaterial)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(SynoraSemanticColor.borderSubtle.color)
        .frame(height: 1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("shell-state")
  }
}
