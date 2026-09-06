import SwiftUI
import SynoraDesignSystem

struct ShellRootView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var model: ShellModel
  @SceneStorage("synora.shell.sidebar-visible") private var persistedSidebarVisible = true
  @SceneStorage("synora.shell.inspector-visible") private var persistedInspectorVisible = true
  @SceneStorage("synora.shell.sidebar-selection") private var persistedSidebarSelection =
    SidebarItem.today.rawValue
  @SceneStorage("synora.shell.record-kind") private var persistedRecordKind = RecordKind.note
    .rawValue
  @SceneStorage("synora.shell.inspector-mode") private var persistedInspectorMode = InspectorMode
    .context.rawValue
  @State private var searchPresented = false

  init() {
    _model = State(initialValue: ShellModel())
  }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      GeometryReader { geometry in
        NavigationSplitView(columnVisibility: columnVisibilityBinding) {
          LibraryNavigation(model: model)
            .navigationSplitViewColumnWidth(
              min: ShellLayoutPolicy.sidebarWidth,
              ideal: ShellLayoutPolicy.sidebarWidth,
              max: ShellLayoutPolicy.sidebarWidth
            )
        } content: {
          RecordListView(model: model)
            .navigationSplitViewColumnWidth(
              min: ShellLayoutPolicy.recordListWidth,
              ideal: ShellLayoutPolicy.recordListWidth,
              max: ShellLayoutPolicy.recordListWidth
            )
        } detail: {
          RecordEditorView(model: model)
            .frame(minWidth: ShellLayoutPolicy.editorMinimumWidth)
        }
        .inspector(isPresented: inspectorBinding) {
          InspectorShellView(model: model)
            .inspectorColumnWidth(
              min: ShellLayoutPolicy.inspectorWidth,
              ideal: ShellLayoutPolicy.inspectorWidth,
              max: ShellLayoutPolicy.inspectorWidth
            )
        }
        .searchable(
          text: searchBinding,
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
          model.restore(
            sidebarSelection: SidebarItem(rawValue: persistedSidebarSelection),
            recordKind: RecordKind(rawValue: persistedRecordKind) ?? .note,
            inspectorMode: InspectorMode(rawValue: persistedInspectorMode) ?? .context
          )
          model.loadRecordsIfNeeded()
          model.reconcile(width: geometry.size.width)
        }
        .onChange(of: geometry.size.width) { _, width in
          model.reconcile(width: width)
        }
        .onChange(of: model.sidebarSelection) { _, selection in
          persistedSidebarSelection = selection?.rawValue ?? ""
        }
        .onChange(of: model.selectedRecordKind) { _, kind in
          persistedRecordKind = kind.rawValue
        }
        .onChange(of: model.inspectorMode) { _, mode in
          persistedInspectorMode = mode.rawValue
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
        hasSelection: model.selectedRecord(for: model.selectedRecordKind) != nil,
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

  private var searchBinding: Binding<String> {
    Binding(
      get: { model.searchQuery },
      set: { model.setSearchQuery($0) }
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
