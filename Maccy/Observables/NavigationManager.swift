import Foundation
import SwiftUI

/// Owns popup selection/scroll/navigation state: the current `selection`, the
/// lead item, hover-vs-keyboard navigation, and the highlight/extend actions
/// bound to arrow-key and shortcut gestures.
@MainActor
@Observable
class NavigationManager {
  private var history: History
  private var footer: Footer

  /// Creates the manager bound to its history and footer.
  init(history: History, footer: Footer) {
    self.history = history
    self.footer = footer
  }

  /// The current multi-capable selection; `willSet` mirrors the selection index
  /// onto each decorator.
  var selection: Selection<HistoryItemDecorator> = Selection() {
    willSet {
      selection.forEach { _, item in item.selectionIndex = -1 }
      newValue.forEach { index, item in item.selectionIndex = index }
    }
  }

  /// The decorator (or footer item, or paste stack) the view should scroll to.
  var scrollTarget: UUID?
  /// The id of the current lead (a history item, footer item, or paste stack).
  var leadSelection: UUID? {
    if let item = leadHistoryItem {
      return item.id
    }
    if let footerItem = footer.selectedItem {
      return footerItem.id
    }
    return history.pasteStack?.id
  }
  private(set) var leadHistoryItem: HistoryItemDecorator? {
    didSet {
      guard oldValue?.id != leadHistoryItem?.id else { return }

      // Cancel the previous lead item's in-flight preview decode so it stops
      // occupying the single serial `ImageProcessor` actor. Previously only
      // `invalidate`/`cleanupImages` cancelled, so navigating off a lead left
      // its preview decoding to completion — a stale-decode pile-up on the
      // actor (worst case under mouse hover). A cached preview survives
      // (`cancelPreviewGeneration` keeps `previewImage`); only an uncached
      // in-flight decode is stopped.
      //
      // Hopped to `@MainActor`: this `didSet` runs in the main-isolated model,
      // but the hop keeps the cancellation decoupled from the selection change.
      let previous = oldValue
      Task { @MainActor in
        previous?.cancelPreviewGeneration()
      }

      let preview = AppState.shared.preview
      if leadHistoryItem != nil {
        preview.resetAutoOpenSuppression()
        preview.scheduleRetarget(lead: leadHistoryItem)
      } else {
        preview.cancelAutoOpen()
        preview.previewedItem = nil
      }
    }
  }

  /// Whether the active paste stack is the current lead selection.
  var pasteStackSelected: Bool {
    return leadSelection != nil && leadSelection == history.pasteStack?.id
  }

  var isManualMultiSelect: Bool = false
  /// Whether a multi-select is active (manually toggled or more than one selected).
  var isMultiSelectInProgress: Bool {
    return isManualMultiSelect || selection.count > 1
  }

  /// A hover-pending id to apply once keyboard navigation ends.
  var hoverSelectionWhileKeyboardNavigating: UUID?
  var isKeyboardNavigating: Bool = true {
    didSet {
      if !isKeyboardNavigating && !isMultiSelectInProgress,
         let hoverSelection = hoverSelectionWhileKeyboardNavigating {
        hoverSelectionWhileKeyboardNavigating = nil
        // Mouse hover selects an already-visible cell — do NOT programatically
        // scroll to it. Routing hover through `scroll(to:)` set `scrollTarget`
        // on every hover, feeding a LazyVStack anchor invalidation that caused
        // a layout-feedback storm. Hover must update selection without
        // disturbing the scroll position.
        selectWithoutScrolling(id: hoverSelection)
      }
    }
  }

  /// Sets `scrollTarget` to drive the list to `id`.
  private func scroll(to id: UUID?, item: HistoryItemDecorator? = nil) {
    scrollTarget = id
  }

  /// Selects by id, dispatching to a history item or footer item if found.
  func select(id: UUID) {
    if let item = history.items.first(where: { $0.id == id }) {
      select(item: item, footerItem: nil)
    } else if let item = footer.items.first(where: { $0.id == id }) {
      select(item: nil, footerItem: item)
    } else {
      select(item: nil, footerItem: nil)
    }
  }

  /// Selects a history and/or footer item and scrolls to it, in one transaction.
  func select(item: HistoryItemDecorator? = nil, footerItem: FooterItem? = nil) {
    withTransaction(Transaction()) {
      selectWithoutScrolling(item: item, footerItem: footerItem)
      scroll(to: item?.id, item: item)
    }
  }

  /// Toggles `item` in the selection (toggling manual multi-select when going
  /// from a single-item selection) and makes it the lead.
  func addToSelection(item: HistoryItemDecorator) {
    var newSelectionState = selection

    if item.isSelected {
      if newSelectionState.count <= 1 {
        isManualMultiSelect = !isManualMultiSelect
      } else {
        newSelectionState.remove(item)
      }
    } else {
      newSelectionState.add(item)
    }

    withTransaction(Transaction()) {
      selection = newSelectionState
      leadHistoryItem = item
      scrollTarget = leadSelection
    }
  }

  /// Extends the selection from `fromItem` to `toItem` — a contiguous range when
  /// `isRange`, otherwise a single add/remove at `toItem`.
  func extendSelection(
    from fromItem: HistoryItemDecorator,
    to toItem: HistoryItemDecorator,
    isRange: Bool
  ) {
    var newSelectionState = selection

    if isRange {
      if let itemRange = history.visibleItems.between(
        from: fromItem,
        to: toItem,
        inOrder: false
      ) {
        newSelectionState = Selection(items: itemRange)
      }
    } else {
      if toItem.isSelected {
        newSelectionState.remove(fromItem)
      } else {
        newSelectionState.add(toItem)
      }
    }

    withTransaction(Transaction()) {
      selection = newSelectionState
      leadHistoryItem = toItem
      scrollTarget = leadSelection
    }
  }

  /// Selects by id without disturbing the scroll position (for hover).
  func selectWithoutScrolling(id: UUID) {
    if let stack = history.pasteStack,
       stack.id == id {
      selectWithoutScrolling(item: nil, footerItem: nil)
    } else if let item = history.items.first(where: { $0.id == id }) {
      if !isMultiSelectInProgress {
        selectWithoutScrolling(item: item, footerItem: nil)
      }
    } else if let item = footer.items.first(where: { $0.id == id }) {
      selectWithoutScrolling(item: nil, footerItem: item)
    } else {
      selectWithoutScrolling(item: nil, footerItem: nil)
    }
  }

  /// Selects a history and/or footer item without scrolling.
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
      selection = .init()
      footer.selectedItem = nil
    }
  }

  /// Sets a single history item as the lead selection, clearing the footer.
  private func selectInHistory(_ item: HistoryItemDecorator) {
    leadHistoryItem = item
    selection = .init(items: [item])
    footer.selectedItem = nil
  }

  /// Sets a footer item as selected, clearing the history lead.
  private func selectInFooter(_ item: FooterItem) {
    leadHistoryItem = nil
    if !isMultiSelectInProgress {
      selection = .init()
    }
    footer.selectedItem = item
  }

  /// Marks keyboard navigation active and selects the given item/footer item.
  private func selectFromKeyboardNavigation(
    item: HistoryItemDecorator? = nil,
    footerItem: FooterItem? = nil
  ) {
    isKeyboardNavigating = true
    isManualMultiSelect = false
    select(item: item, footerItem: footerItem)
  }

  /// Marks keyboard navigation active and extends the selection to `toItem`.
  private func extendHistorySelectionFromKeyboardNavigation(
    from fromItem: HistoryItemDecorator,
    to toItem: HistoryItemDecorator,
    isRange: Bool
  ) {
    isKeyboardNavigating = true
    extendSelection(from: fromItem, to: toItem, isRange: isRange)
  }

  /// Highlights the first visible history item (or clears if none).
  func highlightFirst() {
    if let item = history.firstVisibleItem {
      selectFromKeyboardNavigation(item: item)
    } else {
      selectFromKeyboardNavigation(item: nil)
    }
  }

  /// Moves the highlight one step backward (up), crossing into the footer at the top.
  func highlightPrevious() {
    guard let lead = leadSelection else { return }

    if let historyItem = history.firstVisibleItem(where: { $0.id == lead }) {
      if let nextItem = history.visibleItem(before: historyItem) {
        selectFromKeyboardNavigation(item: nextItem)
      } else if history.pasteStack != nil {
        selectWithoutScrolling(item: nil)
      } else {
        highlightFirst()
      }
    } else if let footerItem = footer.firstVisibleItem(where: { $0.id == lead }) {
      if let nextItem = footer.visibleItem(before: footerItem) {
        selectFromKeyboardNavigation(footerItem: nextItem)
      } else if let nextItem = history.lastVisibleItem {
        selectFromKeyboardNavigation(item: nextItem)
      }
    }
  }

  /// Moves the highlight one step forward (down), crossing into the footer at the bottom.
  func highlightNext(allowCycle: Bool = false) {
    guard let lead = leadSelection else { return }

    if leadSelection == history.pasteStack?.id {
      highlightFirst()
      return
    }

    if let historyItem = history.firstVisibleItem(where: { $0.id == lead }) {
      if let nextItem = history.visibleItem(after: historyItem) {
        selectFromKeyboardNavigation(item: nextItem)
      } else if let nextItem = footer.firstVisibleItem {
        selectFromKeyboardNavigation(footerItem: nextItem)
      } else if allowCycle {
        highlightFirst()
      }
    } else if let footerItem = footer.firstVisibleItem(where: { $0.id == lead }) {
      if let nextItem = footer.visibleItem(after: footerItem) {
        selectFromKeyboardNavigation(footerItem: nextItem)
      } else if let nextItem = footer.firstVisibleItem {
        selectFromKeyboardNavigation(footerItem: nextItem)
      } else if allowCycle {
        // End of footer; cycle to the beginning
        highlightFirst()
      }
    }
  }

  /// Moves the highlight to the last item (footer, or the last history row).
  func highlightLast() {
    guard let lead = leadSelection else { return }

    if let historyItem = history.firstVisibleItem(where: { $0.id == lead }) {
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

  /// Extends the highlight one step forward, or highlights the next item if no lead.
  func extendHighlightToNext() {
    if let leadSelection,
       let leadItem = history.firstVisibleItem(where: {$0.id == leadSelection}) {
      guard let nextItem = history.visibleItem(after: leadItem) else { return }
      extendHistorySelectionFromKeyboardNavigation(from: leadItem, to: nextItem, isRange: false)
    } else {
      highlightNext()
    }
  }

  /// Extends the highlight one step backward, or highlights the previous item if no lead.
  func extendHighlightToPrevious() {
    if let leadSelection,
       let leadItem = history.firstVisibleItem(where: {$0.id == leadSelection}) {
      guard let nextItem = history.visibleItem(before: leadItem) else { return }
      extendHistorySelectionFromKeyboardNavigation(from: leadItem, to: nextItem, isRange: false)
    } else {
      highlightPrevious()
    }
  }

  /// Extends the highlight as a range to the first item, or highlights first if no lead.
  func extendHighlightToFirst() {
    if let leadSelection,
       let leadItem = history.firstVisibleItem(where: {$0.id == leadSelection}) {
      guard let nextItem = history.firstVisibleItem else { return }
      extendHistorySelectionFromKeyboardNavigation(from: leadItem, to: nextItem, isRange: true)
    } else {
      highlightFirst()
    }
  }

  /// Extends the highlight as a range to the last item, or highlights first if no lead.
  func extendHighlightToLast() {
    if let leadSelection,
       let leadItem = history.firstVisibleItem(where: {$0.id == leadSelection}) {
      guard let nextItem = history.lastVisibleItem else { return }
      extendHistorySelectionFromKeyboardNavigation(from: leadItem, to: nextItem, isRange: true)
    } else {
      highlightFirst()
    }
  }

}
