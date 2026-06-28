import AppKit
import Defaults
import Foundation
import Settings
import SwiftUI

@MainActor
@Observable
class AppState {
  static let shared = AppState(history: History.shared, footer: Footer())

  nonisolated let multiSelectionEnabled = false

  var appDelegate: AppDelegate?
  var popup: Popup
  var history: History
  var footer: Footer
  var navigator: NavigationManager
  var preview: SlideoutController

  var searchVisible: Bool {
    if !Defaults[.showSearch] { return false }
    switch Defaults[.searchVisibility] {
    case .always: return true
    case .duringSearch: return !history.searchQuery.isEmpty
    }
  }

  var menuIconText: String {
    var title = history.unpinnedItems.first?.text.shortened(to: 100)
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    title.unicodeScalars.removeAll(where: CharacterSet.newlines.contains)
    return title.shortened(to: 20)
  }

  private let about = About()
  private var settingsWindowController: SettingsWindowController?
  // M10 (master plan): nil the controller (releasing its 6 SwiftUI panes) when
  // the settings window closes, so a once-opened Settings UI doesn't stay
  // resident for the process lifetime. Token stored so the observer removes
  // itself (no accumulation across reopens).
  private var settingsWindowCloseObserver: NSObjectProtocol?

  init(history: History, footer: Footer) {
    self.history = history
    self.footer = footer
    popup = Popup()
    navigator = NavigationManager(history: history, footer: footer)
    preview = SlideoutController(
      onContentResize: { contentWidth in
        Defaults[.windowSize].width = contentWidth
      },
      onSlideoutResize: { previewWidth in
        Defaults[.previewWidth] = previewWidth
      })
    preview.contentWidth = Defaults[.windowSize].width
    preview.slideoutWidth = Defaults[.previewWidth]
  }

  @MainActor
  func select() {
    if !navigator.selection.isEmpty {
      if navigator.isMultiSelectInProgress {
        navigator.isManualMultiSelect = false
        history.startPasteStack(selection: &navigator.selection)
      } else {
        history.select(navigator.selection.first)
      }
    } else if let item = footer.selectedItem {
      // TODO: Use item.suppressConfirmation, but it's not updated!
      if item.confirmation != nil, Defaults[.suppressClearAlert] == false {
        item.showConfirmation = true
      } else {
        item.action()
      }
    } else {
      Clipboard.shared.copy(history.searchQuery)
      history.searchQuery = ""
    }
  }

  /// BS-4.7: pre-warm the history on hotkey-down so the data is ready (or
  /// loading) by the time the popup opens. No-op when items are already loaded
  /// (launch / a previous open / kept current by `consume`); otherwise kicks
  /// `History.load()` on a main-actor task. Nonisolated so it's callable from
  /// the `KeyboardShortcuts` hotkey callback (a nonisolated context); the work
  /// hops to main. Safe to call repeatedly — `load()` is idempotent and
  /// `ContentView.task` only loads when items are still empty.
  func prewarmVisibleWindow() {
    Task { @MainActor in
      let history = AppState.shared.history
      guard history.items.isEmpty else { return }
      try? await history.load()
    }
  }

  @MainActor
  func togglePin() {
    withTransaction(Transaction()) {
      navigator.selection.forEach { _, item in
        history.togglePin(item)
      }
    }
  }

  @MainActor
  func removePasteStack() {
    history.interruptPasteStack()
    navigator.highlightFirst()
  }

  @MainActor
  func deleteSelection() {
    guard let leadItem = navigator.leadHistoryItem else { return }
    let nextUnselectedItem = history.visibleItems.nearest(to: leadItem) { !$0.isSelected }

    withTransaction(Transaction()) {
      navigator.selection.forEach { _, item in
        history.delete(item)
      }
      navigator.select(item: nextUnselectedItem)
    }
  }

  func openAbout() {
    about.openAbout(nil)
  }

  @MainActor
  func openPreferences() {
    if settingsWindowController == nil {
      settingsWindowController = SettingsWindowController(
        panes: [
          Settings.Pane(
            identifier: Settings.PaneIdentifier.general,
            title: NSLocalizedString("Title", tableName: "GeneralSettings", comment: ""),
            toolbarIcon: NSImage.gearshape ?? NSImage()
          ) {
            GeneralSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.storage,
            title: NSLocalizedString("Title", tableName: "StorageSettings", comment: ""),
            toolbarIcon: NSImage.externaldrive ?? NSImage()
          ) {
            StorageSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.appearance,
            title: NSLocalizedString("Title", tableName: "AppearanceSettings", comment: ""),
            toolbarIcon: NSImage.paintpalette ?? NSImage()
          ) {
            AppearanceSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.pins,
            title: NSLocalizedString("Title", tableName: "PinsSettings", comment: ""),
            toolbarIcon: NSImage.pincircle ?? NSImage()
          ) {
            PinsSettingsPane()
              .environment(self)
              .modelContainer(Storage.shared.container)
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.ignore,
            title: NSLocalizedString("Title", tableName: "IgnoreSettings", comment: ""),
            toolbarIcon: NSImage.nosign ?? NSImage()
          ) {
            IgnoreSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.advanced,
            title: NSLocalizedString("Title", tableName: "AdvancedSettings", comment: ""),
            toolbarIcon: NSImage.gearshape2 ?? NSImage()
          ) {
            AdvancedSettingsPane()
          }
        ]
      )
    }
    settingsWindowController?.show()
    settingsWindowController?.window?.orderFrontRegardless()

    // M10: release the controller + its 6 Settings.Pane SwiftUI trees when the
    // window closes (otherwise they stay resident after first open). Keyed on
    // the specific window; removes itself on fire so reopens don't accumulate.
    if let window = settingsWindowController?.window, settingsWindowCloseObserver == nil {
      settingsWindowCloseObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { _ in
        // queue: .main + the observer fires on the main run loop, so
        // MainActor.assumeIsolated is a runtime no-op assertion (never traps).
        // Avoids @unchecked / nonisolated(unsafe): the @Sendable closure hops
        // back into the @MainActor domain to mutate AppState.shared.
        MainActor.assumeIsolated {
          AppState.shared.settingsWindowController = nil
          if let observer = AppState.shared.settingsWindowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            AppState.shared.settingsWindowCloseObserver = nil
          }
        }
      }
    }
  }

  func quit() {
    NSApp.terminate(self)
  }
}
