import AppKit
import SwiftUI

@MainActor
struct SearchFieldAccessibilityReader: NSViewRepresentable {
  func makeNSView(context: Context) -> SearchView {
    SearchView()
  }

  func updateNSView(_ nsView: SearchView, context: Context) {
    nsView.updateSearchFieldIdentifier()
  }

  @MainActor
  final class SearchView: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      updateSearchFieldIdentifier()
    }

    override func layout() {
      super.layout()
      updateSearchFieldIdentifier()
    }

    func updateSearchFieldIdentifier() {
      guard let window else { return }
      let searchField =
        window.contentView
        .flatMap(findSearchField(in:))
        ?? window.toolbar?.items.lazy.compactMap(\.view).compactMap(findSearchField(in:)).first
      guard let searchField else { return }
      searchField.setAccessibilityIdentifier(ShellAccessibilityID.search)
    }

    private func findSearchField(in view: NSView) -> NSSearchField? {
      if let searchField = view as? NSSearchField { return searchField }
      for child in view.subviews {
        if let searchField = findSearchField(in: child) { return searchField }
      }
      return nil
    }
  }
}
