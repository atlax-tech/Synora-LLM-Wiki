import XCTest

@testable import SynoraWiki

final class SynoraWikiTests: XCTestCase {
  func testApplicationBundleIdentity() throws {
    let bundle = Bundle(for: Self.self)
    XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String, "BNDL")
  }

  func testLayoutPolicyKeepsAllColumnsAtWideWidths() {
    let resolution = ShellLayoutPolicy.resolve(
      availableWidth: 1268,
      desiredSidebarVisible: true,
      desiredInspectorVisible: true
    )

    XCTAssertEqual(resolution, .init(sidebarVisible: true, inspectorVisible: true))
  }

  func testLayoutPolicyCollapsesSidebarWhenInspectorIsRequestedInCompactWidth() {
    let resolution = ShellLayoutPolicy.resolve(
      availableWidth: 1267,
      desiredSidebarVisible: true,
      desiredInspectorVisible: true
    )

    XCTAssertEqual(resolution, .init(sidebarVisible: false, inspectorVisible: true))
  }

  func testLayoutPolicyRejectsInspectorBelowEditorMinimumWidth() {
    let resolution = ShellLayoutPolicy.resolve(
      availableWidth: 1087,
      desiredSidebarVisible: true,
      desiredInspectorVisible: true
    )

    XCTAssertEqual(resolution, .init(sidebarVisible: true, inspectorVisible: false))
  }

  func testLayoutPolicyPreservesSidebarPreferenceWhenInspectorIsHidden() {
    let resolution = ShellLayoutPolicy.resolve(
      availableWidth: 1087,
      desiredSidebarVisible: false,
      desiredInspectorVisible: false
    )

    XCTAssertEqual(resolution, .init(sidebarVisible: false, inspectorVisible: false))
  }
}
