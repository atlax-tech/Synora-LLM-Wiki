import Foundation
import XCTest

@MainActor
final class SynoraWikiUITests: XCTestCase {
  private let bundleIdentifier = "tech.atlax.SynoraWiki"
  private let firstNoteID = "record-E4A7E4D7-4E30-4C05-9A3F-6C40D5C4A001"
  private let secondNoteID = "record-E4A7E4D7-4E30-4C05-9A3F-6C40D5C4A002"
  private let firstJournalID = "record-E4A7E4D7-4E30-4C05-9A3F-6C40D5C4B001"

  private struct VisualSize: CaseIterable {
    let name: String
    let width: Int
    let height: Int

    static let allCases = [
      VisualSize(name: "compact", width: 1280, height: 720),
      VisualSize(name: "default", width: 1440, height: 900),
      VisualSize(name: "large", width: 1728, height: 1117),
    ]
  }

  func testCapturesSixShellCandidates() throws {
    let environment = ProcessInfo.processInfo.environment
    let outputDirectory: URL
    if let outputPath = environment["SYNORA_VISUAL_OUTPUT_DIR"], !outputPath.isEmpty {
      outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
    } else {
      outputDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("synora-p1-visual-candidates", isDirectory: true)
    }
    try FileManager.default.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true
    )
    var observations: [String: [String: Any]] = [:]

    for theme in ["light", "dark"] {
      for size in VisualSize.allCases {
        let application = XCUIApplication(bundleIdentifier: "tech.atlax.SynoraWiki")
        launch(application, contentSize: size, theme: theme)

        let window = application.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        application.activate()
        XCTAssertEqual(application.state, .runningForeground, "Synora Wiki must be foreground")
        let contentRoot = application.descendants(matching: .any)["shell-content-root"]
        guard contentRoot.waitForExistence(timeout: 8) else {
          XCTFail("shell-content-root is not exposed")
          application.terminate()
          continue
        }

        let contentMetrics = application.descendants(matching: .any)[
          "shell-content-metrics"
        ]
        XCTAssertTrue(contentMetrics.waitForExistence(timeout: 8))

        XCTAssertTrue(window.exists, "visual target window disappeared")
        let frame = window.frame
        let contentValue =
          (contentMetrics.value as? String).flatMap {
            $0.isEmpty ? nil : $0
          } ?? contentMetrics.label
        print("VISUAL_FRAME_\(theme.uppercased())_\(size.name.uppercased())=\(frame)")
        print("VISUAL_CONTENT_\(theme.uppercased())_\(size.name.uppercased())=\(contentValue)")
        let firstRecord = application.descendants(matching: .any)[
          firstNoteID
        ]
        XCTAssertTrue(firstRecord.waitForExistence(timeout: 8), "fixture records are not loaded")

        let screenshot = window.screenshot()
        let prefix = "shell-\(theme)-\(size.name)"
        let pngURL = outputDirectory.appendingPathComponent("\(prefix).png")
        try screenshot.pngRepresentation.write(to: pngURL)

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = prefix
        attachment.lifetime = .keepAlways
        add(attachment)
        observations["\(theme)-\(size.name)"] = [
          "theme": theme,
          "requestedWindowPoints": ["width": size.width, "height": size.height],
          "contentValue": contentValue,
          "windowFrame": [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "width": frame.size.width,
            "height": frame.size.height,
          ],
        ]
        application.terminate()
      }
    }

    let metadata = try JSONSerialization.data(
      withJSONObject: observations,
      options: [.sortedKeys]
    )
    print("VISUAL_METADATA_BASE64=\(metadata.base64EncodedString())")
  }

  func testMainNavigationSwitchesRecordKindsAndSelection() {
    let application = launchFixture(contentSize: "1728x1117")
    defer { application.terminate() }

    let contextTool = application.descendants(matching: .any)["toolbar-context"]
    let skillsTool = application.descendants(matching: .any)["toolbar-skills"]
    XCTAssertTrue(contextTool.waitForExistence(timeout: 5))
    XCTAssertTrue(skillsTool.waitForExistence(timeout: 5))
    XCTAssertFalse(
      application.descendants(matching: .any)["sidebar-tools-drawer"].exists,
      "Tools must not render as a sidebar module"
    )
    contextTool.click()
    let inspector = application.descendants(matching: .any)["inspector"].firstMatch
    XCTAssertTrue(inspector.waitForExistence(timeout: 5))
    XCTAssertTrue(inspectorModeValue(in: application, labels: ["Context", "上下文"]))

    let allJournals = application.descendants(matching: .any)["sidebar-allJournals"]
    XCTAssertTrue(allJournals.waitForExistence(timeout: 5))
    allJournals.click()
    XCTAssertTrue(
      application.descendants(matching: .any)[firstJournalID].waitForExistence(timeout: 5))

    let allNotes = application.descendants(matching: .any)["sidebar-allNotes"]
    allNotes.click()
    let secondNote = application.descendants(matching: .any)[secondNoteID]
    XCTAssertTrue(secondNote.waitForExistence(timeout: 5))
    secondNote.click()

    let editor = application.descendants(matching: .any)["editor"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    XCTAssertTrue((editor.value as? String)?.contains("Local-first search notes") == true)
  }

  func testToolbarToolsAreIndependentRightSideItems() {
    let application = launchFixture(contentSize: "1728x1117")
    defer { application.terminate() }

    let toolbar = application.toolbars.firstMatch
    XCTAssertTrue(toolbar.waitForExistence(timeout: 5))

    let identifiers = [
      "toolbar-context",
      "toolbar-skills",
      "toggle-inspector",
      "command-palette-button",
    ]
    for identifier in identifiers {
      let item = application.descendants(matching: .any)[identifier]
      XCTAssertTrue(item.waitForExistence(timeout: 5), "missing toolbar item \(identifier)")
    }
    XCTAssertTrue(toolbarSearchButton(in: application).waitForExistence(timeout: 5))

    let expectedLabels = ["Search", "Context", "AI Skills", "Inspector", "Command Palette"]
    let actualLabels = toolbar.buttons.allElementsBoundByIndex
      .map { $0.label == "搜索" ? "Search" : $0.label }
      .filter { expectedLabels.contains($0) }
    XCTAssertEqual(actualLabels, expectedLabels)
  }

  func testToolbarToolsAndCommandPaletteJourney() {
    let application = launchFixture(contentSize: "1728x1117")
    defer { application.terminate() }

    application.typeKey("s", modifierFlags: [.command, .shift])
    XCTAssertTrue(
      application.descendants(matching: .any)["sidebar"].waitForNonExistence(timeout: 5)
    )

    let skillsTool = application.descendants(matching: .any)["toolbar-skills"]
    XCTAssertTrue(skillsTool.waitForExistence(timeout: 5))
    skillsTool.click()

    let inspector = application.descendants(matching: .any)["inspector"].firstMatch
    XCTAssertTrue(inspector.waitForExistence(timeout: 5))
    XCTAssertTrue(inspectorModeValue(in: application, labels: ["AI Skills", "AI 技能"]))

    let commandPaletteTool = application.descendants(matching: .any)["command-palette-button"]
    XCTAssertTrue(commandPaletteTool.waitForExistence(timeout: 5))
    commandPaletteTool.click()
    let palette = application.descendants(matching: .any)["command-palette"]
    XCTAssertTrue(palette.waitForExistence(timeout: 3))
    palette.buttons["Show Journal"].click()
    XCTAssertTrue(palette.waitForNonExistence(timeout: 3))
    XCTAssertTrue(
      application.descendants(matching: .any)[firstJournalID].waitForExistence(timeout: 5))
  }

  func testSearchFocusFiltersRecords() {
    let application = launchFixture()
    defer { application.terminate() }

    let searchButton = toolbarSearchButton(in: application)
    XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
    searchButton.click()

    let nativeSearchField = application.descendants(matching: .textField)[
      "toolbar-search-field"
    ]
    XCTAssertTrue(nativeSearchField.waitForExistence(timeout: 5))
    nativeSearchField.click()
    nativeSearchField.typeText("Local-first")
    nativeSearchField.typeKey(.return, modifierFlags: [])

    XCTAssertTrue(
      application.descendants(matching: .any)[secondNoteID].waitForExistence(timeout: 5))
    let collapsedSearchButton = toolbarSearchButton(in: application)
    XCTAssertTrue(collapsedSearchButton.waitForExistence(timeout: 5))

    application.typeKey("f", modifierFlags: [.command])
    let keyboardSearchField = application.descendants(matching: .textField)[
      "toolbar-search-field"
    ]
    XCTAssertTrue(keyboardSearchField.waitForExistence(timeout: 5))
    keyboardSearchField.click()
    keyboardSearchField.typeText("Local-first")
    keyboardSearchField.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(
      toolbarSearchButton(in: application)
        .waitForExistence(timeout: 5)
    )
  }

  func testThemeToggleChangesOnlyThisSession() {
    let application = launchFixture(contentSize: "1440x900", theme: "light")
    defer { application.terminate() }
    application.activate()

    let themeToggle = application.buttons["theme-toggle"]
    XCTAssertTrue(themeToggle.waitForExistence(timeout: 5))
    XCTAssertEqual(themeToggle.label, "Switch to Dark Mode")

    themeToggle.click()
    XCTAssertTrue(application.buttons["Switch to Light Mode"].waitForExistence(timeout: 5))

    application.buttons["theme-toggle"].click()
    XCTAssertTrue(application.buttons["Switch to Dark Mode"].waitForExistence(timeout: 5))
  }

  private func launchFixture(contentSize: String = "1440x900", theme: String? = nil)
    -> XCUIApplication
  {
    let application = XCUIApplication(bundleIdentifier: bundleIdentifier)
    var environment = [
      "SYNORA_UI_TESTING": "1",
      "SYNORA_FIXTURE": "records",
      "SYNORA_CONTENT_SIZE": contentSize,
      "SYNORA_DISABLE_ANIMATIONS": "1",
    ]
    var arguments = [
      "-SYNORA_UI_TESTING", "1",
      "-SYNORA_FIXTURE", "records",
      "-SYNORA_CONTENT_SIZE", contentSize,
      "-SYNORA_DISABLE_ANIMATIONS", "1",
      "-ApplePersistenceIgnoreState", "YES",
    ]
    if let theme {
      environment["SYNORA_THEME"] = theme
      arguments += ["-SYNORA_THEME", theme]
    }
    application.launchEnvironment = environment
    application.launchArguments = arguments
    application.launch()
    XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 8))
    XCTAssertTrue(
      application.descendants(matching: .any)["shell-content-root"].waitForExistence(timeout: 8)
    )
    return application
  }

  private func inspectorModeValue(in application: XCUIApplication, labels: [String]) -> Bool {
    application.descendants(matching: .any)
      .matching(identifier: "inspector")
      .allElementsBoundByIndex
      .contains { element in
        labels.contains { label in String(describing: element.value).contains(label) }
      }
  }

  private func toolbarSearchButton(in application: XCUIApplication) -> XCUIElement {
    let toolbarButtons = application.toolbars.firstMatch.buttons.allElementsBoundByIndex
    return toolbarButtons.first {
      ["Search", "搜索"].contains($0.label)
    } ?? application.toolbars.firstMatch.buttons.element(boundBy: 1)
  }

  private func launch(_ application: XCUIApplication, contentSize: VisualSize, theme: String) {
    application.launchEnvironment = [
      "SYNORA_UI_TESTING": "1",
      "SYNORA_FIXTURE": "records",
      "SYNORA_CONTENT_SIZE": "\(contentSize.width)x\(contentSize.height)",
      "SYNORA_DISABLE_ANIMATIONS": "1",
      "SYNORA_THEME": theme,
    ]
    application.launchArguments = [
      "-SYNORA_UI_TESTING", "1",
      "-SYNORA_FIXTURE", "records",
      "-SYNORA_CONTENT_SIZE", "\(contentSize.width)x\(contentSize.height)",
      "-SYNORA_DISABLE_ANIMATIONS", "1",
      "-SYNORA_THEME", theme,
      "-ApplePersistenceIgnoreState", "YES",
    ]
    application.launch()
  }
}
