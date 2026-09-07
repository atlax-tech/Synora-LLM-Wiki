import SwiftUI
import SynoraDesignSystem

struct ShellRootView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast
  @State private var model: ShellModel
  @SceneStorage("synora.shell.sidebar-visible") private var persistedSidebarVisible = true
  @SceneStorage("synora.shell.inspector-visible") private var persistedInspectorVisible = false
  @SceneStorage("synora.shell.sidebar-selection") private var persistedSidebarSelection =
    SidebarItem.today.rawValue
  @SceneStorage("synora.shell.record-kind") private var persistedRecordKind = RecordKind.note
    .rawValue
  @SceneStorage("synora.shell.inspector-mode") private var persistedInspectorMode = InspectorMode
    .context.rawValue
  @State private var searchPresented = false
  @State private var windowMetrics: WindowMetrics?
  @State private var themeOverride: ColorScheme?
  @State private var themeTransitionTarget: ColorScheme?
  @State private var themeTransitionOpacity = 0.0

  init() {
    _model = State(initialValue: ShellModel())
    _themeOverride = State(
      initialValue: ShellEnvironment.forcedDarkMode.map { $0 ? .dark : .light }
    )
  }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      GeometryReader { geometry in
        shellContent(geometry: geometry)
      }

      if model.commandPalettePresented {
        ShellCommandPalette(actions: actions)
          .padding(.top, 56)
          .padding(.trailing, 16)
          .transition(.opacity)
          .zIndex(2)
      }

      if let themeTransitionTarget {
        ThemeTransitionOverlay(
          target: themeTransitionTarget,
          opacity: themeTransitionOpacity,
          reduceMotion: reduceMotion || ShellEnvironment.animationsDisabled
        )
        .zIndex(2)
      }
    }
    .overlay(alignment: .bottom) {
      ShellStatusBar(
        selectedRecordKind: model.selectedRecordKind,
        hasSelection: model.selectedRecord(for: model.selectedRecordKind) != nil,
        contentState: model.contentState,
        isInspectorSpaceLimited: !model.inspectorToggleEnabled,
        reduceTransparency: reduceTransparency,
        highContrast: colorSchemeContrast == .increased,
        colorScheme: effectiveColorScheme,
        isThemeTransitioning: themeTransitionTarget != nil,
        toggleTheme: toggleTheme
      )
      .frame(maxWidth: .infinity)
    }
    .animation(
      .easeInOut(
        duration: SynoraMotion.inspector.duration(
          reducingMotion: reduceMotion || ShellEnvironment.animationsDisabled
        )
      ),
      value: model.commandPalettePresented
    )
    .onExitCommand {
      if searchPresented {
        endSearch()
      } else if model.commandPalettePresented {
        model.setCommandPalettePresented(false)
      }
    }
    .focusedSceneValue(\.shellActions, actions)
    .overlay(alignment: .topLeading) {
      Text(" ")
        .font(.system(size: 1))
        .foregroundStyle(.clear)
        .frame(width: 1, height: 1)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metricsAccessibilityValue)
        .accessibilityValue(metricsAccessibilityValue)
        .accessibilityIdentifier(ShellAccessibilityID.contentMetrics)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(ShellAccessibilityID.window)
    .toolbar(id: "shell-toolbar") {
      shellToolbar
    }
    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    .toolbar(removing: .title)
    .toolbarRole(.automatic)
    .preferredColorScheme(themeOverride)
  }

  private func shellContent(geometry: GeometryProxy) -> some View {
    let splitView = NavigationSplitView(columnVisibility: columnVisibilityBinding) {
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
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Shell content")
    .accessibilityValue(metricsAccessibilityValue)
    .accessibilityIdentifier(ShellAccessibilityID.contentRoot)
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
    .background(
      WindowMetricsReader { metrics in
        windowMetrics = metrics
        model.reconcile(width: metrics.contentSize.width)
      }
    )
    .padding(.bottom, 32)

    return splitView
  }

  private var actions: ShellActions {
    ShellActions(
      toggleSidebar: { model.toggleSidebar() },
      focusSearch: { presentSearch() },
      toggleInspector: { model.toggleInspector() },
      toggleCommandPalette: { model.toggleCommandPalette() },
      selectRecordKind: { model.selectRecordKind($0) },
      closeTransientLayer: { model.setCommandPalettePresented(false) },
      inspectorToggleEnabled: model.inspectorToggleEnabled
    )
  }

  @ToolbarContentBuilder
  private var shellToolbar: some CustomizableToolbarContent {
    ToolbarItem(id: "toolbar-flexible-gap", placement: .automatic) {
      Spacer(minLength: 0)
        .frame(width: toolbarGapWidth)
        .accessibilityHidden(true)
    }

    ToolbarItem(id: "search", placement: .automatic) {
      if searchPresented {
        TextField("Search records", text: searchBinding)
          .frame(width: 220)
          .textFieldStyle(.roundedBorder)
          .onSubmit(endSearch)
          .onKeyPress(.return, phases: .down) { _ in
            endSearch()
            return .handled
          }
          .onExitCommand(perform: endSearch)
          .accessibilityLabel("Search records")
          .accessibilityIdentifier(ShellAccessibilityID.toolbarSearchField)
      } else {
        ToolbarIconButton(
          systemImage: "magnifyingglass",
          label: "Search",
          identifier: ShellAccessibilityID.toolbarSearchButton,
          action: presentSearch
        )
      }
    }
    ToolbarSpacer(.fixed)

    ToolbarItem(id: "context", placement: .automatic) {
      ToolbarIconButton(
        systemImage: "square.stack.3d.up",
        label: "Context",
        identifier: ShellAccessibilityID.toolbarContext,
        action: { model.presentInspector(.context) }
      )
    }
    ToolbarSpacer(.fixed)

    ToolbarItem(id: "skills", placement: .automatic) {
      ToolbarIconButton(
        systemImage: "wand.and.stars",
        label: "AI Skills",
        identifier: ShellAccessibilityID.toolbarSkills,
        action: { model.presentInspector(.skills) }
      )
    }
    ToolbarSpacer(.fixed)

    ToolbarItem(id: "inspector", placement: .automatic) {
      ToolbarIconButton(
        systemImage: "sidebar.right",
        label: "Inspector",
        identifier: ShellAccessibilityID.toolbarInspector,
        action: { model.toggleInspector() },
        isEnabled: model.inspectorToggleEnabled
      )
    }
    ToolbarSpacer(.fixed)

    ToolbarItem(id: "command-palette", placement: .automatic) {
      ToolbarIconButton(
        systemImage: "command",
        label: "Command Palette",
        identifier: ShellAccessibilityID.toolbarCommandPalette,
        action: { model.toggleCommandPalette() }
      )
    }
  }

  private var searchBinding: Binding<String> {
    Binding(
      get: { model.searchQuery },
      set: { model.setSearchQuery($0) }
    )
  }

  private var toolbarGapWidth: CGFloat {
    let contentWidth = windowMetrics?.contentSize.width ?? 1440
    return max(0, contentWidth - 865)
  }

  private var metricsAccessibilityValue: String {
    guard let windowMetrics else { return "Measuring content area" }
    let size = windowMetrics.contentSize
    return "\(Int(size.width)) by \(Int(size.height)) points, \(windowMetrics.backingScale)x scale"
  }

  private var effectiveColorScheme: ColorScheme {
    themeOverride ?? colorScheme
  }

  private func presentSearch() {
    searchPresented = true
  }

  private func endSearch() {
    searchPresented = false
  }

  private var themeTransitionSegmentDuration: Double {
    reduceMotion || ShellEnvironment.animationsDisabled ? 0.075 : 0.35
  }

  private func toggleTheme() {
    guard themeTransitionTarget == nil else { return }
    let target: ColorScheme = effectiveColorScheme == .dark ? .light : .dark
    let segmentDuration = themeTransitionSegmentDuration

    themeTransitionTarget = target
    themeTransitionOpacity = 0
    withAnimation(.easeInOut(duration: segmentDuration)) {
      themeTransitionOpacity = 1
    }

    Task { @MainActor in
      let delay = UInt64(segmentDuration * 1_000_000_000)
      try? await Task.sleep(nanoseconds: delay)
      themeOverride = target
      withAnimation(.easeInOut(duration: segmentDuration)) {
        themeTransitionOpacity = 0
      }
      try? await Task.sleep(nanoseconds: delay)
      themeTransitionTarget = nil
    }
  }

  private var columnVisibilityBinding: Binding<NavigationSplitViewVisibility> {
    Binding(
      get: {
        model.effectiveSidebarVisible ? .all : .doubleColumn
      },
      set: { visibility in
        let visible = visibility == .all
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

private struct ToolbarIconButton: View {
  let systemImage: String
  let label: String
  let identifier: String
  let action: () -> Void
  var isEnabled = true

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 15, weight: .medium))
        .frame(width: 32, height: 32)
        .contentShape(.circle)
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.circle)
    .controlSize(.small)
    .disabled(!isEnabled)
    .help(label)
    .accessibilityLabel(label)
    .accessibilityIdentifier(identifier)
  }
}

private struct ShellStatusBar: View {
  let selectedRecordKind: RecordKind
  let hasSelection: Bool
  let contentState: ShellContentState
  let isInspectorSpaceLimited: Bool
  let reduceTransparency: Bool
  let highContrast: Bool
  let colorScheme: ColorScheme
  let isThemeTransitioning: Bool
  let toggleTheme: () -> Void

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
        Label(
          contentState == .loaded ? "Local library" : contentState.title,
          systemImage: contentState == .loaded ? "internaldrive" : contentState.systemImage
        )
        .font(SynoraTypography.metadata.font)
        .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
      }

      ThemeToggleButton(
        colorScheme: colorScheme,
        isTransitioning: isThemeTransitioning,
        toggleTheme: toggleTheme
      )
    }
    .padding(.horizontal, SynoraSpacing.md)
    .frame(height: 32)
    .background(
      reduceTransparency
        ? AnyShapeStyle(SynoraSemanticColor.canvas.color)
        : AnyShapeStyle(.regularMaterial)
    )
    .overlay(alignment: .top) {
      Rectangle()
        .fill(
          highContrast
            ? SynoraSemanticColor.inkSecondary.color
            : SynoraSemanticColor.borderSubtle.color
        )
        .frame(height: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityValue(
      isInspectorSpaceLimited
        ? "Inspector unavailable at this width"
        : (contentState == .loaded ? "Local library" : contentState.title)
    )
    .accessibilityIdentifier(ShellAccessibilityID.shellState)
  }
}

private struct ThemeToggleButton: View {
  let colorScheme: ColorScheme
  let isTransitioning: Bool
  let toggleTheme: () -> Void

  var body: some View {
    Button(action: toggleTheme) {
      Image(systemName: colorScheme == .dark ? "sun.max.fill" : "moon.fill")
    }
    .buttonStyle(.borderless)
    .glassEffect(.regular, in: .circle)
    .controlSize(.small)
    .frame(width: 28, height: 28)
    .contentShape(.circle)
    .disabled(isTransitioning)
    .help(colorScheme == .dark ? "Switch to Light Mode" : "Switch to Dark Mode")
    .accessibilityLabel(colorScheme == .dark ? "Switch to Light Mode" : "Switch to Dark Mode")
    .accessibilityIdentifier(ShellAccessibilityID.themeToggle)
  }
}

private struct ThemeTransitionOverlay: View {
  let target: ColorScheme
  let opacity: Double
  let reduceMotion: Bool

  var body: some View {
    ZStack {
      if reduceMotion {
        (target == .light ? Color.white : Color(red: 0.03, green: 0.04, blue: 0.09))
      } else if target == .light {
        LinearGradient(
          colors: [
            Color(red: 0.97, green: 0.53, blue: 0.28),
            Color(red: 1, green: 0.84, blue: 0.48),
            Color.white,
          ],
          startPoint: .bottom,
          endPoint: .top
        )
        RadialGradient(
          colors: [Color.white.opacity(0.95), Color.white.opacity(0)],
          center: .bottom,
          startRadius: 10,
          endRadius: 260
        )
        .scaleEffect(0.75 + opacity * 0.25)
        .offset(y: 70 * (1 - opacity))
      } else {
        Color(red: 0.03, green: 0.04, blue: 0.09)
        StarField()
          .opacity(0.35 + opacity * 0.65)
      }
    }
    .opacity(opacity)
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct StarField: View {
  private let stars: [(CGFloat, CGFloat, CGFloat, Double)] = [
    (0.12, 0.18, 1.5, 0.75),
    (0.25, 0.34, 1.0, 0.55),
    (0.38, 0.15, 1.2, 0.7),
    (0.52, 0.28, 1.8, 0.8),
    (0.66, 0.12, 1.0, 0.6),
    (0.79, 0.31, 1.4, 0.72),
    (0.9, 0.2, 1.1, 0.55),
    (0.18, 0.58, 1.0, 0.5),
    (0.47, 0.62, 1.3, 0.65),
    (0.72, 0.54, 1.0, 0.6),
    (0.86, 0.72, 1.5, 0.72),
  ]

  var body: some View {
    Canvas { context, size in
      for (x, y, radius, alpha) in stars {
        let point = CGPoint(x: size.width * x, y: size.height * y)
        let rect = CGRect(
          x: point.x - radius,
          y: point.y - radius,
          width: radius * 2,
          height: radius * 2
        )
        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
      }
    }
    .blendMode(.screen)
  }
}
