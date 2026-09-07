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
    private var lastReportedMetrics: WindowMetrics?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      applyContentSizeOverrideIfNeeded()
      report()
    }

    override func layout() {
      super.layout()
      applyContentSizeOverrideIfNeeded()
      report()
    }

    func report() {
      guard let window else { return }
      let metrics = WindowMetrics(
        contentSize: window.contentLayoutRect.size,
        backingScale: window.backingScaleFactor,
        screenFrame: window.screen?.visibleFrame
      )
      guard metrics != lastReportedMetrics else { return }
      lastReportedMetrics = metrics
      Task { @MainActor [weak self] in
        self?.onUpdate?(metrics)
      }
    }

    private func applyContentSizeOverrideIfNeeded() {
      guard let requestedSize = ShellEnvironment.requestedContentSize, let window else { return }

      let currentSize = window.contentLayoutRect.size
      guard
        abs(currentSize.width - requestedSize.width) > 1
          || abs(currentSize.height - requestedSize.height) > 1
      else {
        return
      }

      if window.isZoomed {
        window.zoom(nil)
      }

      let requestedContentRect = NSRect(origin: .zero, size: requestedSize)
      let requestedFrameSize = window.frameRect(forContentRect: requestedContentRect).size
      var frame = window.frame
      var frameSize = requestedFrameSize
      let targetScreen = NSScreen.screens.first {
        $0.visibleFrame.width >= requestedFrameSize.width
          && $0.visibleFrame.height >= requestedFrameSize.height
      }
      let visibleFrame =
        targetScreen?.visibleFrame
        ?? window.screen?.visibleFrame
        ?? NSScreen.main?.visibleFrame
      if !ShellEnvironment.isUITesting, let visibleFrame {
        frameSize.width = min(frameSize.width, visibleFrame.width)
        frameSize.height = min(frameSize.height, visibleFrame.height)
      }
      frame.size = frameSize
      if let visibleFrame {
        frame.origin.x = max(
          visibleFrame.minX,
          min(frame.origin.x, visibleFrame.maxX - frame.width)
        )
        frame.origin.y = max(
          visibleFrame.minY,
          min(frame.origin.y, visibleFrame.maxY - frame.height)
        )
      }
      guard frame != window.frame else { return }
      window.setFrame(frame, display: true)
    }
  }
}
