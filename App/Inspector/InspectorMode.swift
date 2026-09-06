enum InspectorMode: String, CaseIterable, Hashable, Sendable {
  case context
  case skills

  var title: String {
    switch self {
    case .context:
      "Context"
    case .skills:
      "AI Skills"
    }
  }
}
