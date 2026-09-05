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
}
