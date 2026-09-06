import AppKit
import SwiftUI

struct WindowMetrics: Equatable, Sendable {
  let contentSize: CGSize
  let backingScale: CGFloat
  let screenFrame: CGRect?
}

@MainActor
struct WindowMetricsReader: NSViewRepresentable {
  let onUpdate: (WindowMetrics) -> Void

  func makeNSView(context: Context) -> MetricsView {
    let view = MetricsView()
    view.onUpdate = onUpdate
    return view
  }

  func updateNSView(_ nsView: MetricsView, context: Context) {
    nsView.onUpdate = onUpdate
    nsView.report()
  }

  @MainActor
  final class MetricsView: NSView {
    var onUpdate: ((WindowMetrics) -> Void)?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      report()
    }

    override func layout() {
      super.layout()
      report()
    }

    func report() {
      guard let window else { return }
      onUpdate?(
        WindowMetrics(
          contentSize: window.contentLayoutRect.size,
          backingScale: window.backingScaleFactor,
          screenFrame: window.screen?.visibleFrame
        )
      )
    }
  }
}
