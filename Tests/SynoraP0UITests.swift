import XCTest

@MainActor
final class SynoraP0UITests: XCTestCase {
  func testApplicationLaunchesWithWindow() {
    let application = XCUIApplication()
    application.launch()
    let hasWindow = application.windows.firstMatch.waitForExistence(timeout: 5)
    XCTAssertTrue(hasWindow)
    application.terminate()
  }

  func testProbeLaunchesWithAccessibleEditorAndAttachmentAction() {
    let application = XCUIApplication(bundleIdentifier: "tech.atlax.SynoraWiki.P0Probes")
    application.launch()
    XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 5))
    let editor = application.textViews["textkit-editor"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.click()
    XCTAssertTrue(editor.isHittable)
    XCTAssertTrue(application.buttons["insert-attachment"].waitForExistence(timeout: 5))
    application.buttons["insert-attachment"].click()
    XCTAssertTrue(editor.exists)
    application.terminate()
  }
}
