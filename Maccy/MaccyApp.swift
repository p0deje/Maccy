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
      statusItem.button?.appearsDisabled = menuIconAppearsDisable
      if let panel = appState.popup.appDelegate?.panel, panel.menuBarButton == nil {
        panel.menuBarButton = statusItem.button
      }
    }
    .onChange(of: appState.popup.menuPresented) {
      if let event = NSApp.currentEvent, event.type == .leftMouseUp {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if modifierFlags.contains(.option) {
          ignoreEvents.toggle()
          if modifierFlags.contains(.shift) {
            Defaults[.ignoreOnlyNextEvent] = ignoreEvents
          }

          statusItem?.button?.isHighlighted = false
          return
        }
      }

      if appState.popup.menuPresented {
        appState.popup.appDelegate?.panel.open(at: .statusItem)
      } else {
        appState.popup.appDelegate?.panel.close()
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
