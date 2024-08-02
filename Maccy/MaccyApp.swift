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
    // Bridge FloatingPanel and NIB via AppDelegate.
    appState.appDelegate = appDelegate

    disableUnusedGlobalHotkeys()

    Task {
      for await _ in Defaults.updates(.clipboardCheckInterval, initial: false) {
        Clipboard.shared.restart()
      }
    }
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
        .introspectMenuBarExtraWindow { window in
          window.contentView?.translatesAutoresizingMaskIntoConstraints = false
        }
    } label: {
      if showRecentCopyInMenuBar {
        Text(appState.menuIconText)
      }
      Image(nsImage: menuIcon.image)
    }
    .menuBarExtraStyle(.window) // required on Sequoia
    .menuBarExtraAccess(isPresented: $appState.popup.menuPresented) { statusItem in
      self.statusItem = statusItem
      statusItem.button?.appearsDisabled = menuIconAppearsDisable
      if let panel = appState.appDelegate?.panel, panel.menuBarButton == nil {
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
        appState.appDelegate?.panel.open(height: appState.height, at: .statusItem)
      } else {
        appState.appDelegate?.panel.close()
      }
    }
    .onChange(of: ignoreEvents) {
      statusItem?.button?.appearsDisabled = menuIconAppearsDisable
    }
    .onChange(of: enabledPasteboardTypes) {
      statusItem?.button?.appearsDisabled = menuIconAppearsDisable
    }
  }

  private func disableUnusedGlobalHotkeys() {
    let names: [KeyboardShortcuts.Name] = [.delete, .pin]
    KeyboardShortcuts.disable(names)

    NotificationCenter.default.addObserver(
      forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
      object: nil,
      queue: nil
    ) { notification in
      if let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name, names.contains(name) {
        KeyboardShortcuts.disable(name)
      }
    }
  }
}
