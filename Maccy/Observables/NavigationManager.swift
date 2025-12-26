import Foundation
import SwiftUI

@Observable
class NavigationManager { // swiftlint:disable:this type_body_length
  private var history: History
  private var footer: Footer

  init(history: History, footer: Footer) {
    self.history = history
    self.footer = footer
  }

  var selection: Selection<HistoryItemDecorator> = Selection() {
    willSet {
      selection.forEach { _, item in item.selectionIndex = -1 }
      newValue.forEach { index, item in item.selectionIndex = index }
    }
  }

  var scrollTarget: UUID?
  var leadSelection: UUID? {
    if let item = leadHistoryItem {
      return item.id
    }
    if let footerItem = footer.selectedItem {
      return footerItem.id
    }
    return history.pasteStack?.id
  }
  private(set) var leadHistoryItem: HistoryItemDecorator?

  var pasteStackSelected: Bool {
    return leadSelection == history.pasteStack?.id
  }

  var isManualMultiSelect: Bool = false
  var isMultiSelectInProgress: Bool {
    return isManualMultiSelect || selection.count > 1
  }

  var hoverSelectionWhileKeyboardNavigating: UUID?
  var isKeyboardNavigating: Bool = true {
    didSet {
      if !isKeyboardNavigating && !isMultiSelectInProgress,
         let hoverSelection = hoverSelectionWhileKeyboardNavigating {
        hoverSelectionWhileKeyboardNavigating = nil
        select(id: hoverSelection)
      }
    }
  }

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

  private func selectInHistory(_ item: HistoryItemDecorator) {
    leadHistoryItem = item
    selection = .init(items: [item])
    footer.selectedItem = nil
  }

  private func selectInFooter(_ item: FooterItem) {
    leadHistoryItem = nil
    if !isMultiSelectInProgress {
      selection = .init()
    }
    footer.selectedItem = item
  }

  private func selectFromKeyboardNavigation(
    item: HistoryItemDecorator? = nil,
    footerItem: FooterItem? = nil
  ) {
    isKeyboardNavigating = true
    isManualMultiSelect = false
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
      } else if history.pasteStack != nil {
        selectWithoutScrolling(item: nil)
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

    if leadSelection == history.pasteStack?.id {
      highlightFirst()
      return
    }

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

}
