// swiftlint:disable file_length
import AppKit.NSRunningApplication
import Defaults
import Foundation
import Logging
import Observation
import Sauce
import Settings
import SwiftData

@Observable
class History: ItemsContainer { // swiftlint:disable:this type_body_length
  static let shared = History()
  let logger = Logger(label: "org.p0deje.Maccy")

  var items: [HistoryItemDecorator] = []
  var pasteStack: PasteStack?
  static let cacheLimit = 1_000
  var deepSearchActive = false
  var deepSearchLoading = false
  var deepSearchHasMore = false
  var deepSearchError: String?
  var deepSearchPage = 0
  @ObservationIgnored private var deepSearchTask: Task<Void, Never>?
  @ObservationIgnored private var deepSearchRevision = 0

  var pinnedItems: [HistoryItemDecorator] { items.filter(\.isPinned) }
  var unpinnedItems: [HistoryItemDecorator] { items.filter(\.isUnpinned) }

  var searchQuery: String = "" {
    didSet {
      if deepSearchActive { endDeepSearch() }
      throttler.throttle { [self] in
        guard !deepSearchActive else { return }
        updateItems(search.search(string: searchQuery, within: all))

        if searchQuery.isEmpty {
          AppState.shared.navigator.select(item: unpinnedItems.first)
        } else {
          AppState.shared.navigator.highlightFirst()
        }

        AppState.shared.popup.needsResize = true
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

  private let search = Search()
  private let sorter = Sorter()
  private let throttler = Throttler(minimumDelay: 0.2)

  @ObservationIgnored
  private var sessionLog: [Int: HistoryItem] = [:]

  // The distinction between `all` and `items` is the following:
  // - `all` stores the recent cache plus pins, including items hidden by a search
  // - `items` stores only visible history items, updated during a search
  @ObservationIgnored
  var all: [HistoryItemDecorator] = []

  init() {
    Task {
      for await _ in Defaults.updates(.extendedHistory, initial: false) {
        endDeepSearch()
      }
    }

    Task {
      for await _ in Defaults.updates(.size, initial: false) {
        endDeepSearch()
        try? await load()
      }
    }

    Task {
      for await _ in Defaults.updates(.pasteByDefault, initial: false) {
        updateShortcuts()
      }
    }

    Task {
      for await _ in Defaults.updates(.sortBy, initial: false) {
        try? await load()
      }
    }

    Task {
      for await _ in Defaults.updates(.pinTo, initial: false) {
        try? await load()
      }
    }

    Task {
      for await _ in Defaults.updates(.showSpecialSymbols, initial: false) {
        for item in items {
          await updateTitle(item: item, title: item.item.generateTitle())
        }
      }
    }

    Task {
      for await _ in Defaults.updates(.imageMaxHeight, initial: false) {
        for item in items {
          await item.cleanupImages()
        }
      }
    }
  }

  @MainActor
  func load() async throws {
    try enforceRetentionLimit()
    var recent = FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.pin == nil },
      sortBy: [SortDescriptor(\.lastCopiedAt, order: .reverse)]
    )
    recent.fetchLimit = Self.cacheLimit
    let pins = FetchDescriptor<HistoryItem>(predicate: #Predicate { $0.pin != nil })
    let results = try Storage.shared.context.fetch(recent) + Storage.shared.context.fetch(pins)
    all = sorter.sort(results).map { HistoryItemDecorator($0) }
    if !deepSearchActive {
      updateItems(search.search(string: searchQuery, within: all))
    }

    updateShortcuts()
    // Ensure that panel size is proper *after* loading all items.
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func insertIntoStorage(_ item: HistoryItem) throws {
    logger.info("Inserting item with id '\(item.title)'")
    Storage.shared.context.insert(item)
    Storage.shared.context.processPendingChanges()
    try? Storage.shared.context.save()
  }

  @discardableResult
  @MainActor
  func add(_ item: HistoryItem) -> HistoryItemDecorator {
    // Deduplication or finite retention can delete models held by an archive page.
    if deepSearchActive { endDeepSearch() }
    if #available(macOS 15.0, *) {
      try? History.shared.insertIntoStorage(item)
    } else {
      // On macOS 14 the history item needs to be inserted into storage directly after creating it.
      // It was already inserted after creation in Clipboard.swift
    }

    var removedItemIndex: Int?
    if let existingHistoryItem = findSimilarItem(item) {
      if isModified(item) == nil {
        transferContents(from: existingHistoryItem, to: item)
      }
      item.firstCopiedAt = existingHistoryItem.firstCopiedAt
      item.numberOfCopies += existingHistoryItem.numberOfCopies
      item.pin = existingHistoryItem.pin
      item.title = existingHistoryItem.title
      if !item.fromMaccy {
        item.application = existingHistoryItem.application
      }
      logger.info("Removing duplicate item '\(item.title)'")
      removedItemIndex = all.firstIndex(where: { $0.item == existingHistoryItem })
      if let removedItemIndex {
        cleanup(all[removedItemIndex])
      }
      deleteFromStorage(existingHistoryItem)
      if let removedItemIndex {
        all.remove(at: removedItemIndex)
      }
    } else {
      Task {
        Notifier.notify(body: item.title, sound: .write)
      }
    }

    sessionLog[Clipboard.shared.changeCount] = item
    if sessionLog.count > Self.cacheLimit, let oldest = sessionLog.keys.min() {
      sessionLog.removeValue(forKey: oldest)
    }

    let itemDecorator = cacheAddedItem(item, replacing: removedItemIndex)

    do { try enforceRetentionLimit(protecting: item) } catch { logger.error("Failed to limit history: \(error)") }
    trimCache()
    if !deepSearchActive { items = all }
    updateShortcuts()
    try? Storage.shared.context.save()
    return itemDecorator
  }

  @MainActor
  private func cacheAddedItem(_ item: HistoryItem, replacing removedItemIndex: Int?) -> HistoryItemDecorator {
    var itemDecorator: HistoryItemDecorator
    if let pin = item.pin {
      itemDecorator = HistoryItemDecorator(item, shortcuts: KeyShortcut.create(character: pin))
      if let removedItemIndex {
        // If pin to bottom -> last element should be inserted to the removedItemIndex - 1
        // Or to the last all array place.
        all.insert(itemDecorator, at: min(removedItemIndex, all.count))
      } else {
        all.append(itemDecorator)
      }
    } else {
      itemDecorator = HistoryItemDecorator(item)

      let sortedItems = sorter.sort(all.map(\.item) + [item])
      if let index = sortedItems.firstIndex(of: item) {
        all.insert(itemDecorator, at: index)
      }

      if !deepSearchActive { items = all }
      updateUnpinnedShortcuts()
      AppState.shared.popup.needsResize = true
    }

    return itemDecorator
  }

  // Retention is independent of the display cache and the archive-search toggle.
  // -1 (and invalid nonpositive legacy values) never trigger automatic deletion.
  @MainActor
  private func enforceRetentionLimit(protecting addedItem: HistoryItem? = nil) throws {
    let limit = Defaults[.size]
    guard limit > 0 else { return }
    try Storage.shared.context.save()
    let order: SortDescriptor<HistoryItem>
    switch Defaults[.sortBy] {
    case .firstCopiedAt: order = SortDescriptor(\.firstCopiedAt, order: .reverse)
    case .numberOfCopies: order = SortDescriptor(\.numberOfCopies, order: .reverse)
    default: order = SortDescriptor(\.lastCopiedAt, order: .reverse)
    }
    var descriptor = FetchDescriptor<HistoryItem>(predicate: #Predicate { $0.pin == nil }, sortBy: [order])
    descriptor.fetchOffset = limit
    if let addedItem, addedItem.pin == nil {
      // A new copy always gets a slot, even when older items have higher copy counts.
      let protectedID = addedItem.persistentModelID
      descriptor.predicate = #Predicate { $0.pin == nil && $0.persistentModelID != protectedID }
      descriptor.fetchOffset = limit - 1
    }
    descriptor.includePendingChanges = false
    descriptor.fetchLimit = 100
    var overflow = try Storage.shared.context.fetch(descriptor)
    while !overflow.isEmpty {
      let ids = Set(overflow.map(\.persistentModelID))
      all.filter { ids.contains($0.item.persistentModelID) }.forEach(cleanup)
      all.removeAll { ids.contains($0.item.persistentModelID) }
      items.removeAll { ids.contains($0.item.persistentModelID) }
      sessionLog.removeValues { ids.contains($0.persistentModelID) }
      overflow.forEach(deleteFromStorage)
      try Storage.shared.context.save()
      overflow = try Storage.shared.context.fetch(descriptor)
    }
  }

  @MainActor
  private func trimCache() {
    let recent = all.filter(\.isUnpinned).sorted { $0.item.lastCopiedAt > $1.item.lastCopiedAt }
    let evicted = Set(recent.dropFirst(Self.cacheLimit))
    evicted.forEach(cleanup)
    all.removeAll { evicted.contains($0) }
  }

  @MainActor
  func startDeepSearch(nextPage: Bool = false) {
    guard Defaults[.extendedHistory] else { return }
    deepSearchTask?.cancel()
    deepSearchRevision += 1
    let revision = deepSearchRevision
    let query = searchQuery
    deepSearchPage = nextPage ? deepSearchPage + 1 : 0
    let page = deepSearchPage
    deepSearchActive = true
    deepSearchLoading = true
    deepSearchError = nil
    deepSearchHasMore = false
    items = []
    AppState.shared.navigator.select()
    let container = Storage.shared.container
    deepSearchTask = Task { @MainActor in
      do {
        let ids = try await Task.detached {
          let worker = ArchiveSearch(modelContainer: container)
          return try await worker.find(query: query, page: page)
        }.value
        guard !Task.isCancelled, revision == deepSearchRevision else { return }
        deepSearchHasMore = ids.count > ArchiveSearch.pageSize
        items = ids.prefix(ArchiveSearch.pageSize).compactMap { id in
          guard let item = Storage.shared.context.model(for: id) as? HistoryItem else { return nil }
          return all.first { $0.item.persistentModelID == id } ?? HistoryItemDecorator(item)
        }
        updateShortcuts()
        AppState.shared.navigator.highlightFirst()
      } catch {
        guard !Task.isCancelled, revision == deepSearchRevision else { return }
        deepSearchError = error.localizedDescription
      }
      deepSearchLoading = false
      AppState.shared.popup.needsResize = true
    }
  }

  func endDeepSearch() {
    deepSearchTask?.cancel()
    deepSearchRevision += 1
    deepSearchActive = false
    deepSearchLoading = false
    deepSearchHasMore = false
    deepSearchError = nil
    items = search.search(string: searchQuery, within: all).map(\.object)
    updateShortcuts()
    AppState.shared.navigator.select(item: items.first)
    AppState.shared.popup.needsResize = true
  }

  @MainActor
  private func withLogging(_ msg: String, _ block: () throws -> Void) rethrows {
    func dataCounts() -> String {
      let historyItemCount = try? Storage.shared.context.fetchCount(FetchDescriptor<HistoryItem>())
      let historyContentCount = try? Storage.shared.context.fetchCount(FetchDescriptor<HistoryItemContent>())
      return "HistoryItem=\(historyItemCount ?? 0) HistoryItemContent=\(historyContentCount ?? 0)"
    }

    logger.info("\(msg) Before: \(dataCounts())")
    try? block()
    logger.info("\(msg) After: \(dataCounts())")
  }

  @MainActor
  func clear() {
    endDeepSearch()
    withLogging("Clearing history") {
      all.forEach { item in
        if item.isUnpinned {
          cleanup(item)
        }
      }
      all.removeAll(where: \.isUnpinned)
      sessionLog.removeValues { $0.pin == nil }
      items = all

      try? Storage.shared.context.transaction {
        try? Storage.shared.context.delete(
          model: HistoryItem.self,
          where: #Predicate { $0.pin == nil }
        )
        try? Storage.shared.context.delete(
          model: HistoryItemContent.self,
          where: #Predicate { $0.item?.pin == nil }
        )
      }
      Storage.shared.context.processPendingChanges()
      try? Storage.shared.context.save()
    }

    Clipboard.shared.clear()
    AppState.shared.popup.close()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func clearAll() {
    endDeepSearch()
    withLogging("Clearing all history") {
      all.forEach { item in
        cleanup(item)
      }
      all.removeAll()
      sessionLog.removeAll()
      items = all

      do {
        let context = Storage.shared.context
        try context.transaction {
          // Bulk deletion cannot remove children with live inverse relationships.
          try context.delete(
            model: HistoryItemContent.self,
            where: #Predicate { $0.item == nil }
          )
          try context.delete(model: HistoryItem.self)
          try context.delete(model: HistoryItemContent.self)
        }
      } catch {
        logger.error("Failed to clear storage: \(String(reflecting: error))")
      }
      Storage.shared.context.processPendingChanges()
      try? Storage.shared.context.save()
    }

    Clipboard.shared.clear()
    AppState.shared.popup.close()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func delete(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    cleanup(item)
    withLogging("Removing history item") {
      deleteFromStorage(item.item)
      Storage.shared.context.processPendingChanges()
      try? Storage.shared.context.save()
    }

    all.removeAll { $0 == item }
    items.removeAll { $0 == item }
    sessionLog.removeValues { $0 == item.item }

    updateUnpinnedShortcuts()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  private func transferContents(from existingItem: HistoryItem, to newItem: HistoryItem) {
    deleteContents(of: newItem)
    newItem.contents = existingItem.contents
    existingItem.contents = []
  }

  @MainActor
  private func deleteFromStorage(_ item: HistoryItem) {
    deleteContents(of: item)
    Storage.shared.context.delete(item)
  }

  @MainActor
  private func deleteContents(of item: HistoryItem) {
    item.contents.forEach(Storage.shared.context.delete)
  }

  @MainActor
  private func cleanup(_ item: HistoryItemDecorator) {
    item.cleanupImages()
  }

  @MainActor
  func select(_ item: HistoryItemDecorator?, flags modifierFlags: NSEvent.ModifierFlags) {
    guard let item else {
      return
    }

    // Archive selections do not enter the cache until a new clipboard event is saved.
    // A new copy preserves the original archived record; deduplication stays recent-only.
    if modifierFlags.isEmpty {
      AppState.shared.popup.close()
      Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
      if Defaults[.pasteByDefault] {
        Clipboard.shared.paste()
      }
    } else {
      switch HistoryItemAction(modifierFlags) {
      case .copy:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
      case .paste:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
        Clipboard.shared.paste()
      case .pasteWithoutFormatting:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item, removeFormatting: true)
        Clipboard.shared.paste()
      case .unknown:
        return
      }
    }

    Task {
      searchQuery = ""
    }
  }

  @MainActor
  func startPasteStack(selection: inout Selection<HistoryItemDecorator>, flags modifierFlags: NSEvent.ModifierFlags) {
    guard AppState.shared.multiSelectionEnabled else { return }
    guard let item = selection.first else { return }
    PasteStack.initializeIfNeeded()

    let stack = PasteStack(items: selection.items, modifierFlags: modifierFlags)
    pasteStack = stack

    logger.info("Initialising PasteStack with \(stack.items.count) items")
    logger.info("Copying \(item.item.title) from PasteStack")

    if modifierFlags.isEmpty {
      AppState.shared.popup.close()
      Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
    } else {
      switch HistoryItemAction(modifierFlags) {
      case .copy:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
      case .paste:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
      case .pasteWithoutFormatting:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item, removeFormatting: true)
        Clipboard.shared.paste()
      case .unknown:
        return
      }
    }

    Task {
      searchQuery = ""
    }
  }

  func handlePasteStack() {
    guard let stack = pasteStack else {
      return
    }

    guard let pasted = stack.items.first else {
      pasteStack = nil
      logger.info("PasteStack is empty")
      return
    }

    logger.info("PasteStack pasted \(pasted.item.title)")

    stack.items.removeFirst()

    guard let item = stack.items.first else {
      pasteStack = nil
      logger.info("PasteStack is empty")
      return
    }

    logger.info("Copying \(item.item.title) from PasteStack. \(stack.items.count) items remaining in stack.")

    Task {
      if stack.modifierFlags.isEmpty {
        await Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
      } else {
        switch HistoryItemAction(stack.modifierFlags) {
        case .copy:
          await Clipboard.shared.copy(item.item)
        case .paste:
          await Clipboard.shared.copy(item.item)
        case .pasteWithoutFormatting:
          await Clipboard.shared.copy(item.item, removeFormatting: true)
        case .unknown:
          return
        }
      }
    }
  }

  func interruptPasteStack() {
    guard pasteStack != nil else {
      return
    }
    logger.info("Interrupting PasteStack")
    pasteStack = nil
  }

  @MainActor
  func togglePin(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    item.togglePin()
    if !all.contains(item), item.isPinned { all.append(item) }
    trimCache()
    try? Storage.shared.context.save()

    let sortedItems = sorter.sort(all.map(\.item))
    if let currentIndex = all.firstIndex(of: item),
       let newIndex = sortedItems.firstIndex(of: item.item) {
      all.remove(at: currentIndex)
      all.insert(item, at: newIndex)
    }

    items = all

    searchQuery = ""
    updateUnpinnedShortcuts()
    if item.isUnpinned {
      AppState.shared.navigator.scrollTarget = item.id
    }
  }

  @MainActor
  private func findSimilarItem(_ item: HistoryItem) -> HistoryItem? {
    if let duplicate = all.first(where: { $0.item != item && $0.item.supersedes(item) }) {
      return duplicate.item
    }

    return isModified(item)
  }

  private func isModified(_ item: HistoryItem) -> HistoryItem? {
    if let modified = item.modified, sessionLog.keys.contains(modified) {
      return sessionLog[modified]
    }

    return nil
  }

  private func updateItems(_ newItems: [Search.SearchResult]) {
    items = newItems.map { result in
      let item = result.object
      item.highlight(searchQuery, result.ranges)

      return item
    }

    updateUnpinnedShortcuts()
  }

  private func updateShortcuts() {
    for item in pinnedItems {
      if let pin = item.item.pin {
        item.shortcuts = KeyShortcut.create(character: pin)
      }
    }

    updateUnpinnedShortcuts()
  }

  @MainActor
  private func updateTitle(item: HistoryItemDecorator, title: String) {
    item.title = title
    item.item.title = title
  }

  private func updateUnpinnedShortcuts() {
    let visibleUnpinnedItems = unpinnedItems.filter(\.isVisible)
    for item in visibleUnpinnedItems {
      item.shortcuts = []
    }

    var index = 1
    for item in visibleUnpinnedItems.prefix(9) {
      item.shortcuts = KeyShortcut.create(character: String(index))
      index += 1
    }
  }
}
