import Foundation
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

  func testInspectorModeChangePreservesRecordSelection() {
    let model = ShellModel()
    let selectedID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

    model.selectRecord(selectedID, in: .note)
    let selectionBeforeModeChange = model.selectedRecordIDs

    model.setInspectorMode(.skills)

    XCTAssertEqual(model.selectedRecordIDs, selectionBeforeModeChange)
    XCTAssertEqual(model.selectedRecordIDs[.note] ?? nil, selectedID)
  }

  func testRecordListProjectionGroupsMonthsAndKeepsStableOrder() {
    let records = [
      Record(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        kind: .note,
        title: "Older same-day record",
        summary: "Summary",
        modifiedAt: testDate(year: 2026, month: 8, day: 22)
      ),
      Record(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        kind: .note,
        title: "Newer same-day record",
        summary: "Summary",
        modifiedAt: testDate(year: 2026, month: 8, day: 22)
      ),
      Record(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        kind: .note,
        title: "September record",
        summary: "Summary",
        modifiedAt: testDate(year: 2026, month: 9, day: 1)
      ),
    ]

    let groups = RecordListProjection.filterAndGroup(records: records, query: "")

    XCTAssertEqual(groups.map(\.month.title), ["2026-09", "2026-08"])
    XCTAssertEqual(
      groups[1].records.map(\.id.uuidString),
      [
        "00000000-0000-0000-0000-000000000001",
        "00000000-0000-0000-0000-000000000002",
      ])
  }

  func testRecordListProjectionFiltersCaseInsensitiveAndChineseText() {
    let records = [
      Record(
        id: UUID(),
        kind: .note,
        title: "Local Search",
        summary: "A searchable note",
        modifiedAt: testDate(year: 2026, month: 9, day: 1)
      ),
      Record(
        id: UUID(),
        kind: .note,
        title: "本地记录",
        summary: "关于搜索的摘要",
        modifiedAt: testDate(year: 2026, month: 9, day: 2)
      ),
    ]

    XCTAssertEqual(RecordListProjection.filterAndGroup(records: records, query: "local").count, 1)
    XCTAssertEqual(RecordListProjection.filterAndGroup(records: records, query: "搜索").count, 1)
    XCTAssertTrue(RecordListProjection.filterAndGroup(records: records, query: "missing").isEmpty)
  }

  private func testDate(year: Int, month: Int, day: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
  }
}
