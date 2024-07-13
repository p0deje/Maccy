import Defaults
import KeyboardShortcuts
import MenuBarExtraAccess
import Settings
import SwiftData
import SwiftUI

@main
struct MaccyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  init() {
    Clipboard.shared.onNewCopy(History.shared.add)
    Clipboard.shared.start()

    // FloatingPanel is only accessible via AppDelegate.
    appState.popup.appDelegate = appDelegate
  }

  @Default(.menuIcon) private var menuIcon
  @Default(.showInStatusBar) private var showMenuIcon
  @Default(.showRecentCopyInMenuBar) private var showRecentCopyInMenuBar

  @Default(.enabledPasteboardTypes) private var enabledPasteboardTypes
  @Default(.ignoreEvents) private var ignoreEvents

  @Bindable private var appState = AppState.shared
  @State private var statusItem: NSStatusItem?

  private var menuIconAppearsDisable: Bool { ignoreEvents || enabledPasteboardTypes.isEmpty }

  var body: some Scene {
    MenuBarExtra(isInserted: $showMenuIcon) {
      EmptyView()
    } label: {
      if showRecentCopyInMenuBar {
        Text(appState.menuIconText)
      }
      Image(nsImage: menuIcon.image)
    }
    .menuBarExtraAccess(isPresented: $appState.popup.menuPresented) { statusItem in
      self.statusItem = statusItem

      if let panel = appState.popup.appDelegate?.panel {
        if panel.menuBarButton == nil {
          panel.menuBarButton = statusItem.button
        }

        if appState.popup.menuPresented {
          panel.open(at: .statusItem)
        } else {
          panel.close()
        }
      }
    }
    .onChange(of: ignoreEvents) {
      statusItem?.button?.appearsDisabled = menuIconAppearsDisable
    }
    .onChange(of: enabledPasteboardTypes) {
      statusItem?.button?.appearsDisabled = menuIconAppearsDisable
    }
  }
}
