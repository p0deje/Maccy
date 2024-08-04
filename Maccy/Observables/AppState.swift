import AppKit
import Foundation
import Settings

@Observable
class AppState: Sendable {
  static let shared = AppState()

  var appDelegate: AppDelegate? = nil
  var popup: Popup
  var history: History
  var footer: Footer

  var height: CGFloat = 0
  var needsResize = false

  var scrollTarget: UUID?
  var selection: UUID? = nil {
    didSet {
      // Cancel scrolling
      scrollTarget = nil

      history.selectedItem = nil
      footer.selectedItem = nil

      if let item = history.items.first(where: { $0.id == selection }) {
        history.selectedItem = item
      } else if let item = footer.items.first(where: { $0.id == selection }) {
        footer.selectedItem = item
      }
    }
  }

  var menuIconText: String {
    var title = history.unpinnedItems.first?.text.shortened(to: 100).trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    title.unicodeScalars.removeAll(where: CharacterSet.newlines.contains)
    return title.shortened(to: 20)
  }

  private let about = About()
  private var settingsWindowController: SettingsWindowController? = nil

  init() {
    history = History.shared
    footer = Footer()
    popup = Popup()
  }

  @MainActor
  func select() {
    if let item = history.selectedItem, item.isVisible {
      history.select(item)
    } else if let item = footer.selectedItem {
      if item.confirmation != nil {
        item.showConfirmation = true
      } else {
        item.action()
      }
    } else {
      Clipboard.shared.copy(history.searchQuery)
      history.searchQuery = ""
    }
  }

  func highlightFirst() {
    if let item = history.items.first(where: \.isVisible) {
      selection = item.id
    }
  }

  func highlightPrevious() {
    if let selectedItem = history.selectedItem {
      if let nextItem = history.items.filter(\.isVisible).item(before: selectedItem) {
        selection = nextItem.id
      }
    } else if let selectedItem = footer.selectedItem {
      if let nextItem = footer.items.filter(\.isVisible).item(before: selectedItem) {
        selection = nextItem.id
      } else if selectedItem == footer.items.first(where: \.isVisible),
                let nextItem = history.items.last(where: \.isVisible) {
        selection = nextItem.id
      }
    }
  }

  func highlightNext() {
    if let selectedItem = history.selectedItem {
      if let nextItem = history.items.filter(\.isVisible).item(after: selectedItem) {
        selection = nextItem.id
      } else if selectedItem == history.items.filter(\.isVisible).last,
                let nextItem = footer.items.first(where: \.isVisible) {
        selection = nextItem.id
      }
    } else if let selectedItem = footer.selectedItem {
      if let nextItem = footer.items.filter(\.isVisible).item(after: selectedItem) {
        selection = nextItem.id
      }
    } else {
      selection = footer.items.first(where: \.isVisible)?.id
    }
  }

  func highlightLast() {
    if let selectedItem = history.selectedItem {
      if selectedItem == history.items.filter(\.isVisible).last,
         let nextItem = footer.items.first(where: \.isVisible) {
        selection = nextItem.id
      } else {
        selection = history.items.last(where: \.isVisible)?.id
      }
    } else if footer.selectedItem != nil {
      selection = footer.items.last(where: \.isVisible)?.id
    } else {
      selection = footer.items.first(where: \.isVisible)?.id
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
            toolbarIcon: NSImage.gearshape!
          ) {
            GeneralSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.storage,
            title: NSLocalizedString("Title", tableName: "StorageSettings", comment: ""),
            toolbarIcon: NSImage.externaldrive!
          ) {
            StorageSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.appearance,
            title: NSLocalizedString("Title", tableName: "AppearanceSettings", comment: ""),
            toolbarIcon: NSImage.paintpalette!
          ) {
            AppearanceSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.pins,
            title: NSLocalizedString("Title", tableName: "PinsSettings", comment: ""),
            toolbarIcon: NSImage.pincircle!
          ) {
            PinsSettingsPane()
              .modelContainer(Storage.shared.container)
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.ignore,
            title: NSLocalizedString("Title", tableName: "IgnoreSettings", comment: ""),
            toolbarIcon: NSImage.nosign!
          ) {
            IgnoreSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.advanced,
            title: NSLocalizedString("Title", tableName: "AdvancedSettings", comment: ""),
            toolbarIcon: NSImage.gearshape2!
          ) {
            AdvancedSettingsPane()
          },
        ]
      )
    }
    settingsWindowController?.show()
    settingsWindowController?.window?.orderFrontRegardless()
  }

  func quit() {
    NSApp.terminate(self)
  }
}
