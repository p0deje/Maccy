import Defaults
import KeyboardShortcuts
import Settings
import SwiftData
import SwiftUI

@main
struct MaccyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  init() {
    Clipboard.shared.onNewCopy(History.shared.add)
    Clipboard.shared.start()
  }

  @Default(.menuIcon) private var menuIcon
  @Default(.showInStatusBar) private var showMenuIcon
  @Default(.showRecentCopyInMenuBar) private var showRecentCopyInMenuBar

  @State private var history = History.shared

  var body: some Scene {
    MenuBarExtra(isInserted: $showMenuIcon) {
      EmptyView()
    } label: {
      if showRecentCopyInMenuBar {
        Text(history.firstUnpinnedItem?.text.trimmingCharacters(in: .whitespacesAndNewlines).shortened(to: 20) ?? "")
      }
      Image(nsImage: menuIcon.image)
    }
  }
}
