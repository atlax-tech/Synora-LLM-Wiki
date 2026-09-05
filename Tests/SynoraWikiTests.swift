import XCTest

final class SynoraWikiTests: XCTestCase {
  func testApplicationBundleIdentity() throws {
    let bundle = Bundle(for: Self.self)
    XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String, "BNDL")
  }
}
