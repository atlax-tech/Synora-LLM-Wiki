import Testing

@testable import SynoraPlatform

@Test
func currentReportHasStableBuildFacts() {
  let report = PlatformReport.current

  #expect(report.architecture == "arm64")
  #expect(report.swiftVersion == "6.2")
  #expect(!report.operatingSystem.isEmpty)
  #expect(!report.foundationModels.isEmpty)
}
