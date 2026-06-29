import AppKit
import Defaults
import Foundation
import Settings
import SwiftUI

/// Top-level app state holding the shared observable models (`History`,
/// `Footer`, `Popup`, `NavigationManager`, `SlideoutController`) and the
/// actions the UI binds to (select, pin, delete, open preferences, …).
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

  /// Whether the search field is shown, from `showSearch` + `searchVisibility`.
  var searchVisible: Bool {
    if !Defaults[.showSearch] { return false }
    switch Defaults[.searchVisibility] {
    case .always: return true
    case .duringSearch: return !history.searchQuery.isEmpty
    }
  }

  /// Shortened text of the most recent unpinned item, for the menu-bar icon.
  var menuIconText: String {
    var title = history.unpinnedItems.first?.text.shortened(to: 100)
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    title.unicodeScalars.removeAll(where: CharacterSet.newlines.contains)
    return title.shortened(to: 20)
  }

  private let about = About()
  private var settingsWindowController: SettingsWindowController?
  /// Token for the close observer that nils the controller (releasing its six
  /// SwiftUI panes) when the settings window closes, so a once-opened Settings
  /// UI doesn't stay resident for the process lifetime. Stored so the observer
  /// removes itself (no accumulation across reopens).
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

  /// Resolves the current selection into an action: a multi-select starts a
  /// paste stack, a single history item is selected (copy/paste), a footer item
  /// runs its action (optionally after confirmation), and an empty selection
  /// with a search query copies the query text.
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
      // item.suppressConfirmation is not yet wired to the live checkbox state.
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

  /// Pre-warm the history on hotkey-down so the data is ready (or loading) by
  /// the time the popup opens. No-op when items are already loaded; otherwise
  /// kicks `History.load()` on a main-actor task. Nonisolated so it's callable
  /// from the `KeyboardShortcuts` hotkey callback (a nonisolated context); the
  /// work hops to main. Safe to call repeatedly — `load()` is idempotent and
  /// `ContentView.task` only loads when items are still empty.
  func prewarmVisibleWindow() {
    Task { @MainActor in
      let history = AppState.shared.history
      guard history.items.isEmpty else { return }
      try? await history.load()
    }
  }

  /// Toggles the pin state of every selected history item in one transaction.
  @MainActor
  func togglePin() {
    withTransaction(Transaction()) {
      navigator.selection.forEach { _, item in
        history.togglePin(item)
      }
    }
  }

  /// Aborts an in-progress paste stack and re-highlights the first item.
  @MainActor
  func removePasteStack() {
    history.interruptPasteStack()
    navigator.highlightFirst()
  }

  /// Deletes every selected history item and moves selection to the nearest
  /// remaining unselected item, all in one transaction.
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

  /// Opens the About window.
  func openAbout() {
    about.openAbout(nil)
  }

  /// Lazily builds (once) and shows the Settings window, registering a
  /// close observer that releases its controller and SwiftUI panes on close.
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

    // Release the controller and its six `Settings.Pane` SwiftUI trees when the
    // window closes (otherwise they stay resident after first open). Keyed on
    // the specific window; the observer removes itself on fire so reopens don't
    // accumulate.
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

  /// Terminates the application.
  func quit() {
    NSApp.terminate(self)
  }
}
