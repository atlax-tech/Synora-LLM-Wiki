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

  func testCapturesThreeShellCandidates() throws {
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

    for size in VisualSize.allCases {
      let application = XCUIApplication(bundleIdentifier: "tech.atlax.SynoraWiki")
      launch(application, contentSize: size)

      XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 8))
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

      let frame = application.windows.firstMatch.frame
      let contentValue =
        (contentMetrics.value as? String).flatMap {
          $0.isEmpty ? nil : $0
        } ?? contentMetrics.label
      print("VISUAL_FRAME_\(size.name.uppercased())=\(frame)")
      print("VISUAL_CONTENT_\(size.name.uppercased())=\(contentValue)")
      let firstRecord = application.descendants(matching: .any)[
        firstNoteID
      ]
      XCTAssertTrue(firstRecord.waitForExistence(timeout: 8), "fixture records are not loaded")

      let screenshot = application.windows.firstMatch.screenshot()
      let pngURL = outputDirectory.appendingPathComponent("shell-\(size.name).png")
      try screenshot.pngRepresentation.write(to: pngURL)

      let attachment = XCTAttachment(screenshot: screenshot)
      attachment.name = "shell-\(size.name)"
      attachment.lifetime = .keepAlways
      add(attachment)
      observations[size.name] = [
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

    let metadata = try JSONSerialization.data(
      withJSONObject: observations,
      options: [.sortedKeys]
    )
    print("VISUAL_METADATA_BASE64=\(metadata.base64EncodedString())")
  }

  func testMainNavigationSwitchesRecordKindsAndSelection() {
    let application = launchFixture(contentSize: "1280x720")
    defer { application.terminate() }

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

  func testSidebarInspectorAndCommandPaletteJourney() {
    let application = launchFixture(contentSize: "1440x900")
    defer { application.terminate() }

    let inspector = application.descendants(matching: .any)["inspector"].firstMatch
    let inspectorToggle = application.buttons["toggle-inspector"]
    XCTAssertTrue(inspector.waitForExistence(timeout: 5))
    inspectorToggle.click()
    XCTAssertTrue(inspector.waitForNonExistence(timeout: 3))
    inspectorToggle.click()
    XCTAssertTrue(inspector.waitForExistence(timeout: 5))

    let skillsMode = application.radioButtons["AI 技能"]
    XCTAssertTrue(skillsMode.waitForExistence(timeout: 5))
    skillsMode.click()
    XCTAssertEqual(inspector.value as? String, "AI 技能")

    application.buttons["command-palette-button"].click()
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

    let searchButton = application.buttons["搜索"]
    XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
    searchButton.click()
    let searchField: XCUIElement =
      if application.searchFields["search"].firstMatch.exists {
        application.searchFields["search"].firstMatch
      } else {
        application.searchFields["搜索记录"].firstMatch
      }
    XCTAssertTrue(searchField.waitForExistence(timeout: 5))
    searchField.click()
    searchField.typeText("Local-first")

    XCTAssertTrue(
      application.descendants(matching: .any)[secondNoteID].waitForExistence(timeout: 5))
  }

  private func launchFixture(contentSize: String = "1440x900") -> XCUIApplication {
    let application = XCUIApplication(bundleIdentifier: bundleIdentifier)
    application.launchEnvironment = [
      "SYNORA_UI_TESTING": "1",
      "SYNORA_FIXTURE": "records",
      "SYNORA_CONTENT_SIZE": contentSize,
      "SYNORA_DISABLE_ANIMATIONS": "1",
    ]
    application.launchArguments = [
      "-SYNORA_UI_TESTING", "1",
      "-SYNORA_FIXTURE", "records",
      "-SYNORA_CONTENT_SIZE", contentSize,
      "-SYNORA_DISABLE_ANIMATIONS", "1",
      "-ApplePersistenceIgnoreState", "YES",
    ]
    application.launch()
    XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 8))
    XCTAssertTrue(
      application.descendants(matching: .any)["shell-content-root"].waitForExistence(timeout: 8)
    )
    return application
  }

  private func launch(_ application: XCUIApplication, contentSize: VisualSize) {
    application.launchEnvironment = [
      "SYNORA_UI_TESTING": "1",
      "SYNORA_FIXTURE": "records",
      "SYNORA_CONTENT_SIZE": "\(contentSize.width)x\(contentSize.height)",
      "SYNORA_DISABLE_ANIMATIONS": "1",
    ]
    application.launchArguments = [
      "-SYNORA_UI_TESTING", "1",
      "-SYNORA_FIXTURE", "records",
      "-SYNORA_CONTENT_SIZE", "\(contentSize.width)x\(contentSize.height)",
      "-SYNORA_DISABLE_ANIMATIONS", "1",
      "-ApplePersistenceIgnoreState", "YES",
    ]
    application.launch()
  }
}
