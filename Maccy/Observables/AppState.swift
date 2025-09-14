import AppKit
import Defaults
import Foundation
import Settings
import SwiftUI

@Observable
class AppState: Sendable {
  static let shared = AppState()

  var appDelegate: AppDelegate?
  var popup: Popup
  var history: History
  var footer: Footer

  var scrollTarget: UUID?
  var leadSelection: UUID? {
    if let item = leadHistoryItem {
      return item.id
    }
    return footer.selectedItem?.id
  }
  private(set) var leadHistoryItem: HistoryItemDecorator?

  private func scroll(to id: UUID?, item: HistoryItemDecorator? = nil) {
    scrollTarget = id
  }

  func select(id: UUID) {
    if let item = history.items.first(where: { $0.id == id }) {
      select(item: item, footerItem: nil)
    } else if let item = footer.items.first(where: { $0.id == id }) {
      select(item: nil, footerItem: item)
    } else {
      select(item: nil, footerItem: nil)
    }
  }

  func select(item: HistoryItemDecorator? = nil, footerItem: FooterItem? = nil) {
    withTransaction(Transaction()) {
      selectWithoutScrolling(item: item, footerItem: footerItem)
      scroll(to: item?.id, item: item)
    }
  }

  func addToSelection(item: HistoryItemDecorator) {
    var newSelectionState = history.selection

    if item.isSelected {
      newSelectionState.remove(item)
    } else {
      newSelectionState.add(item)
    }

    withTransaction(Transaction()) {
      history.selection = newSelectionState
      leadHistoryItem = item
      scrollTarget = leadSelection
    }
  }

  func extendSelection(
    from fromItem: HistoryItemDecorator,
    to toItem: HistoryItemDecorator,
    isRange: Bool
  ) {
    var newSelectionState = history.selection

    if isRange {
      if let itemRange = history.visibleItems.between(
        from: fromItem,
        to: toItem
      ) {
        newSelectionState = Selection(items: Array(itemRange))
      }
    } else {
      if toItem.isSelected {
        newSelectionState.remove(fromItem)
      } else {
        newSelectionState.add(toItem)
      }
    }

    withTransaction(Transaction()) {
      history.selection = newSelectionState
      leadHistoryItem = toItem
      scrollTarget = leadSelection
    }
  }

  func selectWithoutScrolling(id: UUID) {
    if let item = history.items.first(where: { $0.id == id }) {
      selectWithoutScrolling(item: item, footerItem: nil)
    } else if let item = footer.items.first(where: { $0.id == id }) {
      selectWithoutScrolling(item: nil, footerItem: item)
    } else {
      selectWithoutScrolling(item: nil, footerItem: nil)
    }
  }

  func selectWithoutScrolling(
    item: HistoryItemDecorator? = nil,
    footerItem: FooterItem? = nil
  ) {
    if let item = item {
      selectInHistory(item)
    } else if let footerItem = footerItem {
      selectInFooter(footerItem)
    } else {
      leadHistoryItem = nil
      history.selection = .init()
      footer.selectedItem = nil
    }
  }

  private func selectInHistory(_ item: HistoryItemDecorator) {
    leadHistoryItem = item
    history.selection = .init(items: [item])
    footer.selectedItem = nil
  }

  private func selectInFooter(_ item: FooterItem) {
    leadHistoryItem = nil
    history.selection = .init()
    footer.selectedItem = item
  }

  var hoverSelectionWhileKeyboardNavigating: UUID?
  var isKeyboardNavigating: Bool = true {
    didSet {
      if let hoverSelection = hoverSelectionWhileKeyboardNavigating {
        hoverSelectionWhileKeyboardNavigating = nil
        select(id: hoverSelection)
      }
    }
  }

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

  init() {
    history = History.shared
    footer = Footer()
    popup = Popup()
  }

  @MainActor
  func select() {
    if !history.selection.isEmpty {
      history.select(history.selection.first)
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

  private func selectFromKeyboardNavigation(
    item: HistoryItemDecorator? = nil,
    footerItem: FooterItem? = nil
  ) {
    isKeyboardNavigating = true
    select(item: item, footerItem: footerItem)
  }

  private func extendHistorySelectionFromKeyboardNavigation(
    from fromItem: HistoryItemDecorator,
    to toItem: HistoryItemDecorator,
    isRange: Bool
  ) {
    isKeyboardNavigating = true
    extendSelection(from: fromItem, to: toItem, isRange: isRange)
  }

  func highlightFirst() {
    if let item = history.items.first(where: \.isVisible) {
      selectFromKeyboardNavigation(item: item)
    }
  }

  func highlightPrevious() {
    guard let lead = leadSelection else { return }

    if let historyItem = history.visibleItems.first(where: { $0.id == lead }) {
      if let nextItem = history.visibleItems.item(before: historyItem) {
        selectFromKeyboardNavigation(item: nextItem)
      } else {
        highlightFirst()
      }
    } else if let footerItem = footer.visibleItems.first(where: { $0.id == lead }) {
      if let nextItem = footer.visibleItems.item(before: footerItem) {
        selectFromKeyboardNavigation(footerItem: nextItem)
      } else if let nextItem = history.lastVisibleItem {
        selectFromKeyboardNavigation(item: nextItem)
      }
    }
  }

  func highlightNext(allowCycle: Bool = false) {
    guard let lead = leadSelection else { return }

    if let historyItem = history.visibleItems.first(where: { $0.id == lead }) {
      if let nextItem = history.visibleItems.item(after: historyItem) {
        selectFromKeyboardNavigation(item: nextItem)
      } else if let nextItem = footer.firstVisibleItem {
        selectFromKeyboardNavigation(footerItem: nextItem)
      } else if allowCycle {
        highlightFirst()
      }
    } else if let footerItem = footer.visibleItems.first(where: { $0.id == lead }) {
      if let nextItem = footer.visibleItems.item(after: footerItem) {
        selectFromKeyboardNavigation(footerItem: nextItem)
      } else if let nextItem = footer.firstVisibleItem {
        selectFromKeyboardNavigation(footerItem: nextItem)
      } else if allowCycle {
        // End of footer; cycle to the beginning
        highlightFirst()
      }
    }
  }

  func highlightLast() {
    guard let lead = leadSelection else { return }

    if let historyItem = history.visibleItems.first(where: { $0.id == lead }) {
      if historyItem == history.lastVisibleItem,
         let nextItem = footer.firstVisibleItem {
        selectFromKeyboardNavigation(footerItem: nextItem)
      } else {
        selectFromKeyboardNavigation(item: history.lastVisibleItem)
      }
    } else if footer.selectedItem != nil {
      selectFromKeyboardNavigation(footerItem: footer.lastVisibleItem)
    } else {
      selectFromKeyboardNavigation(footerItem: footer.firstVisibleItem)
    }
  }

  func extendHighlightToNext() {
    if let leadSelection,
       let leadItem = history.visibleItems.first(where: {$0.id == leadSelection}) {
      guard let nextItem = history.visibleItems.item(after: leadItem) else { return }
      extendHistorySelectionFromKeyboardNavigation(from: leadItem, to: nextItem, isRange: false)
    } else {
      highlightNext()
    }
  }

  func extendHighlightToPrevious() {
    if let leadSelection,
       let leadItem = history.visibleItems.first(where: {$0.id == leadSelection}) {
      guard let nextItem = history.visibleItems.item(before: leadItem) else { return }
      extendHistorySelectionFromKeyboardNavigation(from: leadItem, to: nextItem, isRange: false)
    } else {
      highlightPrevious()
    }
  }

  func extendHighlightToFirst() {
    if let leadSelection,
       let leadItem = history.visibleItems.first(where: {$0.id == leadSelection}) {
      guard let nextItem = history.firstVisibleItem else { return }
      extendHistorySelectionFromKeyboardNavigation(from: leadItem, to: nextItem, isRange: true)
    } else {
      highlightFirst()
    }
  }

  func extendHighlightToLast() {
    if let leadSelection,
       let leadItem = history.visibleItems.first(where: {$0.id == leadSelection}) {
      guard let nextItem = history.lastVisibleItem else { return }
      extendHistorySelectionFromKeyboardNavigation(from: leadItem, to: nextItem, isRange: true)
    } else {
      highlightFirst()
    }
  }

  func openAbout() {
    about.openAbout(nil)
  }

  @MainActor
  func openPreferences() { // swiftlint:disable:this function_body_length
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
              .environment(self)
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
          }
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
