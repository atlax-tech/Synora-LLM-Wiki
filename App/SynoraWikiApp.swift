import SwiftUI

@main
struct SynoraWikiApp: App {
  var body: some Scene {
    WindowGroup("Synora Wiki", id: "main") {
      ShellRootView()
    }
    .defaultSize(width: 1440, height: 900)
  }
}
