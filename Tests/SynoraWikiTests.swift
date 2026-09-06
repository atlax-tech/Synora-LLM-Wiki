import XCTest

@testable import SynoraWiki

@MainActor
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

  func testSidebarSectionsExposeStableP1NavigationAndCounts() {
    XCTAssertEqual(SidebarSections.all.count, 4)
    XCTAssertEqual(SidebarSections.all[0].items, [.today, .inbox])
    XCTAssertEqual(SidebarSections.all[1].items, [.allNotes, .topics, .tags, .favorites, .trash])
    XCTAssertEqual(
      SidebarSections.all[2].items, [.allJournals, .journalYears, .travel, .life, .daily, .ideas])
    XCTAssertEqual(SidebarSections.all[3].items, [.context, .skills])
  }

  func testSidebarRecordSelectionProjectsIntoRecordKind() {
    let model = ShellModel()

    model.selectSidebarItem(.allJournals)

    XCTAssertEqual(model.sidebarSelection, .allJournals)
    XCTAssertEqual(model.selectedRecordKind, .journal)
  }

  func testSidebarToolSelectionProjectsIntoInspectorMode() {
    let model = ShellModel()

    model.selectSidebarItem(.skills)

    XCTAssertEqual(model.sidebarSelection, .skills)
    XCTAssertEqual(model.inspectorMode, .skills)
    XCTAssertTrue(model.desiredInspectorVisible)
  }

  func testShellModelRestoresSceneStateWithoutChangingLayoutPreference() {
    let model = ShellModel(desiredSidebarVisible: false, desiredInspectorVisible: true)

    model.restore(sidebarSelection: .favorites, recordKind: .note, inspectorMode: .context)

    XCTAssertEqual(model.sidebarSelection, .favorites)
    XCTAssertEqual(model.selectedRecordKind, .note)
    XCTAssertEqual(model.inspectorMode, .context)
    XCTAssertFalse(model.desiredSidebarVisible)
    XCTAssertTrue(model.desiredInspectorVisible)
  }
}
