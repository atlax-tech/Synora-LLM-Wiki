enum InspectorMode: String, CaseIterable, Hashable, Sendable {
  case context
  case skills

  var title: String {
    switch self {
    case .context:
      String(localized: "Context")
    case .skills:
      String(localized: "AI Skills")
    }
  }
}
