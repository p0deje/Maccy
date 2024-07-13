import AppKit.NSRunningApplication
import Defaults
import Foundation
import Observation
import Sauce
import Settings
import SwiftData

@Observable
class History {
  static let shared = History()

  var items: [HistoryItemDecorator] = []
  var selectedItem: HistoryItemDecorator? {
    willSet {
      selectedItem?.isSelected = false
      newValue?.isSelected = true
    }
  }

  var searchQuery: String = "" {
    didSet {
      throttler.throttle { [self] in
        updateItems(
          sorter.sort(
            search
              .search(string: searchQuery, within: items.map(\.item))
              .map(\.object)
          )
        )

        if searchQuery.isEmpty {
          AppState.shared.selection = firstUnpinnedItem?.id
        } else {
          AppState.shared.highlightFirst()
        }
      }
    }
  }

  var pressedShortcutItem: HistoryItemDecorator? {
    guard let event = NSApp.currentEvent else {
      return nil
    }

    let modifierFlags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting(.capsLock)

    guard HistoryItemAction(modifierFlags) != .unknown else {
      return nil
    }

    let key = Sauce.shared.key(for: Int(event.keyCode))
    return items.first { $0.shortcuts.contains(where: { $0.key == key }) }
  }

  var firstUnpinnedItem: HistoryItemDecorator? {
    items.first(where: \.isUnpinned)
  }

  private let search = Search()
  private var sorter = Sorter(by: Defaults[.sortBy])
  private let throttler = Throttler(minimumDelay: 0.2)

  private var sessionLog: [Int: HistoryItem] = [:]

  init() {
    Task {
      for await _ in Defaults.updates(.pasteByDefault, initial: false) {
        updateShortcuts()
      }
    }

    Task {
      for await value in Defaults.updates(.sortBy, initial: false) {
        sorter = Sorter(by: value)
        try? await load()
      }
    }

    Task {
      for await _ in Defaults.updates(.showSpecialSymbols, initial: false) {
        items.forEach { item in
          let title = item.item.generateTitle()
          item.title = title
          item.item.title = title
        }
      }
    }
  }

  @MainActor
  func load() async throws {
    let descriptor = FetchDescriptor<HistoryItem>()
    let results = try SwiftDataManager.shared.container.mainContext.fetch(descriptor)
    items = sorter.sort(results).map { HistoryItemDecorator($0) }

    updateShortcuts()
  }

  @MainActor
  func add(_ item: HistoryItem) {
    if let existingHistoryItem = findSimilarItem(item) {
      if isModified(item) == nil {
        item.contents = existingHistoryItem.contents
      }
      item.firstCopiedAt = existingHistoryItem.firstCopiedAt
      item.numberOfCopies += existingHistoryItem.numberOfCopies
      item.pin = existingHistoryItem.pin
      item.title = existingHistoryItem.title
      if !item.fromMaccy {
        item.application = existingHistoryItem.application
      }
      SwiftDataManager.shared.container.mainContext.delete(existingHistoryItem)
      items.removeAll { $0.item == existingHistoryItem }
    } else {
      Task {
        Notifier.notify(body: item.title, sound: .write)
      }
    }

    sessionLog[Clipboard.shared.changeCount] = item

    var itemDecorator: HistoryItemDecorator
    if let pin = item.pin {
      itemDecorator = HistoryItemDecorator(item, shortcuts: KeyShortcut.create(character: pin))
    } else {
      itemDecorator = HistoryItemDecorator(item)
    }

    let sortedItems = sorter.sort(items.map(\.item) + [item])
    if let index = sortedItems.firstIndex(of: item) {
      items.insert(itemDecorator, at: index)
    }

    updateUnpinnedShortcuts()
  }

  @MainActor
  func clear() {
    items.removeAll(where: \.isUnpinned)
    try? SwiftDataManager.shared.container.mainContext.delete(
      model: HistoryItem.self,
      where: #Predicate { $0.pin == nil }
    )
  }

  @MainActor
  func clearAll() {
    items.removeAll()
    try? SwiftDataManager.shared.container.mainContext.delete(model: HistoryItem.self)
  }

  @MainActor
  func delete(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    SwiftDataManager.shared.container.mainContext.delete(item.item)
    items.removeAll { $0 == item }
    updateUnpinnedShortcuts()
  }

  @MainActor
  func select(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    let modifierFlags = NSApp.currentEvent?.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting(.capsLock) ?? []

    if modifierFlags.isEmpty {
      NSApp.hide(self)
      Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
      if Defaults[.pasteByDefault] {
        Clipboard.shared.paste()
      }
    } else {
      switch HistoryItemAction(modifierFlags) {
      case .copy:
        NSApp.hide(self)
        Clipboard.shared.copy(item.item)
      case .paste:
        NSApp.hide(self)
        Clipboard.shared.copy(item.item)
        Clipboard.shared.paste()
      case .pasteWithoutFormatting:
        NSApp.hide(self)
        Clipboard.shared.copy(item.item, removeFormatting: true)
        Clipboard.shared.paste()
      case .unknown:
        return
      }
    }

    searchQuery = ""
  }

  @MainActor
  func togglePin(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    item.togglePin()

    let sortedItems = sorter.sort(items.map(\.item))
    if let currentIndex = items.firstIndex(of: item),
       let newIndex = sortedItems.firstIndex(of: item.item) {
      items.remove(at: currentIndex)
      items.insert(item, at: newIndex)
    }

    updateUnpinnedShortcuts()
    // TODO: Scroll to pinned item
  }

  @MainActor
  private func findSimilarItem(_ item: HistoryItem) -> HistoryItem? {
    let descriptor = FetchDescriptor<HistoryItem>()
    if let all = try? SwiftDataManager.shared.container.mainContext.fetch(descriptor) {
      let duplicates = all.filter({ $0 == item || $0.supersedes(item) })
      if duplicates.count > 1 {
        return duplicates.first(where: { $0 != item })
      } else {
        return isModified(item)
      }
    }

    return item
  }

  private func isModified(_ item: HistoryItem) -> HistoryItem? {
    if let modified = item.modified, sessionLog.keys.contains(modified) {
      return sessionLog[modified]
    }

    return nil
  }

  private func updateItems(_ newItems: [HistoryItem]) {
    for item in items {
      if newItems.contains(where: { $0 == item.item }) {
        item.highlight(searchQuery)
        if !item.isVisible {
          item.isVisible = true
        }
      } else {
        if item.isVisible {
          item.isVisible = false
        }
      }
    }

    updateUnpinnedShortcuts()
  }

  private func updateShortcuts() {
    for item in items.filter(\.isPinned) {
      if let pin = item.item.pin {
        item.shortcuts = KeyShortcut.create(character: pin)
      }
    }

    updateUnpinnedShortcuts()
  }

  private func updateUnpinnedShortcuts() {
    let visibleUnpinnedItems = items.filter { $0.isVisible && $0.isUnpinned }
    for item in visibleUnpinnedItems {
      item.shortcuts = []
    }

    var index = 1
    for item in visibleUnpinnedItems.prefix(10) {
      item.shortcuts = KeyShortcut.create(character: String(index))
      index += 1
    }
  }
}
