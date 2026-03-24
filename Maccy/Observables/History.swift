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

  var pinnedItems: [HistoryItemDecorator] { items.filter(\.isPinned) }
  var unpinnedItems: [HistoryItemDecorator] { items.filter(\.isUnpinned) }

  var allTags: [String] {
    Array(Set(all.flatMap(\.tags))).sorted()
  }

  var searchQuery: String = "" {
    didSet {
      guard oldValue != searchQuery else {
        return
      }
      throttler.throttle { [self] in
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

    if let chars = event.characters,
       let rawChars = event.charactersIgnoringModifiers,
       chars != rawChars {
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

  // Batching for inserts/saves to reduce churn under heavy clipboard activity
  @ObservationIgnored
  private var pendingInserts: [HistoryItem] = []
  @ObservationIgnored
  private var saveWorkItem: DispatchWorkItem?

  @ObservationIgnored
  private var sessionLog: [Int: HistoryItem] = [:]

  // The distinction between `all` and `items` is the following:
  // - `all` stores all history items, even the ones that are currently hidden by a search
  // - `items` stores only visible history items, updated during a search
  @ObservationIgnored
  var all: [HistoryItemDecorator] = []

  // Pagination support for unlimited history
  @ObservationIgnored
  private let paginationManager = PaginationManager()

  @ObservationIgnored
  var totalCount: Int {
    if Defaults[.isUnlimitedHistory] {
      return paginationManager.totalCount
    }
    return all.count
  }

  @ObservationIgnored
  var isLoadingMore: Bool {
    paginationManager.isLoading
  }

  @ObservationIgnored
  var hasMoreItems: Bool {
    paginationManager.hasMoreItemsAfter
  }

  @ObservationIgnored
  var hasMoreItemsBefore: Bool {
    paginationManager.hasMoreItemsBefore
  }

  @ObservationIgnored
  var windowStartIndex: Int {
    paginationManager.windowStartIndex
  }

  @ObservationIgnored
  var windowEndIndex: Int {
    paginationManager.windowEndIndex
  }

  init() {
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
      for await _ in Defaults.updates(.sortOrder, initial: false) {
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

    Task {
      for await _ in Defaults.updates(.isUnlimitedHistory, initial: false) {
        // Reload history when switching between limited and unlimited modes
        // This ensures proper storage handling for both directions
        try? await load()
      }
    }

    Task {
      for await _ in Defaults.updates(.previewImageMaxSize, initial: false) {
        for item in items {
          await item.cleanupImages()
        }
      }
    }

    Task {
      for await _ in Defaults.updates(.isUnlimitedHistory, initial: false) {
        // Reload history when switching between limited and unlimited modes
        // This ensures proper storage handling for both directions
        try? await load()
      }
    }

    Task {
      for await _ in Defaults.updates(.previewImageMaxSize, initial: false) {
        for item in items {
          await item.sizeImages()
        }
      }
    }
  }

  @MainActor
  func load() async throws {
    all.removeAll()

    if Defaults[.isUnlimitedHistory] {
      // Use pagination manager for unlimited history
      try await paginationManager.load()
      all = paginationManager.allLoadedItems
    } else {
      // Load all items for limited history
      let descriptor = FetchDescriptor<HistoryItem>()
      let results = try Storage.shared.context.fetch(descriptor)
      all = sorter.sort(results).map { HistoryItemDecorator($0) }
      limitHistorySize(to: Defaults[.size])
    }

    items = all

    updateShortcuts()
    // Ensure that panel size is proper *after* loading all items.
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func loadMoreItems() async {
    guard Defaults[.isUnlimitedHistory] else { return }

    do {
      try await paginationManager.loadNextWindow()
      all = paginationManager.allLoadedItems
      items = all
      updateUnpinnedShortcuts()
      AppState.shared.popup.needsResize = true
    } catch {
      logger.error("Failed to load more items: \(error.localizedDescription)")
    }
  }

  @MainActor
  func loadPreviousItems() async {
    guard Defaults[.isUnlimitedHistory] else { return }

    do {
      try await paginationManager.loadPreviousWindow()
      all = paginationManager.allLoadedItems
      items = all
      updateUnpinnedShortcuts()
      AppState.shared.popup.needsResize = true
    } catch {
      logger.error("Failed to load previous items: \(error.localizedDescription)")
    }
  }

  @MainActor
  func jumpToFirst() async {
    guard Defaults[.isUnlimitedHistory] else { return }

    do {
      try await paginationManager.jumpToFirst()
      all = paginationManager.allLoadedItems
      items = all
      updateUnpinnedShortcuts()
      AppState.shared.popup.needsResize = true
    } catch {
      logger.error("Failed to jump to first: \(error.localizedDescription)")
    }
  }

  @MainActor
  func jumpToLast() async {
    guard Defaults[.isUnlimitedHistory] else { return }

    do {
      try await paginationManager.jumpToLast()
      all = paginationManager.allLoadedItems
      items = all
      updateUnpinnedShortcuts()
      AppState.shared.popup.needsResize = true
    } catch {
      logger.error("Failed to jump to last: \(error.localizedDescription)")
    }
  }

  @MainActor
  private func limitHistorySize(to maxSize: Int) {
    let unpinned = all.filter(\.isUnpinned)
    if unpinned.count >= maxSize {
      unpinned[maxSize...].forEach(delete)
    }
  }

  @MainActor
  func insertIntoStorage(_ item: HistoryItem) throws {
    logger.info("Inserting item with id '\(item.title)'")
    enqueueInsert(item)
  }

  @discardableResult
  @MainActor
  func add(_ item: HistoryItem, shouldAppend: Bool = false) -> HistoryItemDecorator {
    if #available(macOS 15.0, *) {
      try? History.shared.insertIntoStorage(item)
    } else {
      // On macOS 14 the history item needs to be inserted into storage directly after creating it.
      // It was already inserted after creation in Clipboard.swift
    }

    // Handle append mode
    if shouldAppend, !all.isEmpty {
      // Find the most recent unpinned item that is NOT the same content as what we're appending
      let unpinnedItems = all.filter { $0.item.pin == nil }
      let differentItems = unpinnedItems.filter { $0.item.text != item.text }

      guard let mostRecentUnpinned = differentItems.max(by: { $0.item.lastCopiedAt < $1.item.lastCopiedAt }) else {
        // No different items, fall through to normal add
        return add(item, shouldAppend: false)
      }

      let topItem = mostRecentUnpinned.item

      // Only append to text-based items
      if let existingText = topItem.text, let newText = item.text {
        let combinedText = existingText + "\n" + newText
        let combinedData = combinedText.data(using: .utf8)

        if let stringContent = topItem.contents.first(where: {
          NSPasteboard.PasteboardType($0.type) == .string
        }) {
          stringContent.value = combinedData
          topItem.lastCopiedAt = Date.now
          topItem.numberOfCopies += 1
          topItem.title = topItem.generateTitle()

          Storage.shared.context.delete(item)

          mostRecentUnpinned.title = topItem.title
          items = all

          // Copy combined text back to system clipboard
          Defaults[.ignoreOnlyNextEvent] = true
          Defaults[.ignoreEvents] = true
          Clipboard.shared.copy(combinedText)

          return mostRecentUnpinned
        }
      }
    }

    var removedItemIndex: Int?
    if let existingHistoryItem = findSimilarItem(item) {
      if isModified(item) == nil {
        item.contents = existingHistoryItem.contents
      }
      item.firstCopiedAt = existingHistoryItem.firstCopiedAt
      item.lastCopiedAt = Date.now
      if item.lastCopiedAt <= item.firstCopiedAt {
        item.lastCopiedAt = item.firstCopiedAt.addingTimeInterval(1)
      }
      item.numberOfCopies += existingHistoryItem.numberOfCopies
      item.pin = existingHistoryItem.pin
      item.secret = existingHistoryItem.secret
      item.title = existingHistoryItem.title
      if !item.fromMaccy {
        item.application = existingHistoryItem.application
      }
      logger.info("Removing duplicate item '\(item.title)'")
      Storage.shared.context.delete(existingHistoryItem)
      removedItemIndex = all.firstIndex(where: { $0.item == existingHistoryItem })
      if let removedItemIndex {
        all.remove(at: removedItemIndex)
      }
    } else {
      Task {
        Notifier.notify(body: item.title, sound: .write)
      }
    }

    // Remove exceeding items. Do this after the item is added to avoid removing something
    // if a duplicate was found as then the size already stayed the same.
    if !Defaults[.isUnlimitedHistory] {
      limitHistorySize(to: Defaults[.size] - 1)
    }

    // Always update the sessionLog with the current item to ensure its properties are preserved
    sessionLog[Clipboard.shared.changeCount] = item

    var itemDecorator: HistoryItemDecorator
    if let pin = item.pin {
      itemDecorator = HistoryItemDecorator(item, shortcuts: KeyShortcut.create(character: pin))
      // Keep pins in the same place for duplicate updates.
      if let removedItemIndex {
        all.insert(itemDecorator, at: removedItemIndex)
      } else {
        let sortedItems = sorter.sort(all.map(\.item) + [item])
        if let index = sortedItems.firstIndex(of: item) {
          all.insert(itemDecorator, at: index)
        }
      }
    } else {
      itemDecorator = HistoryItemDecorator(item)

      if Defaults[.isUnlimitedHistory] {
        // Use pagination manager for unlimited history
        paginationManager.handleNewItem(itemDecorator)
        all = paginationManager.allLoadedItems
      } else {
        let sortedItems = sorter.sort(all.map(\.item) + [item])
        if let index = sortedItems.firstIndex(of: item) {
          all.insert(itemDecorator, at: index)
        }
      }
    }

    items = all
    updateUnpinnedShortcuts()
    AppState.shared.popup.needsResize = true

    return itemDecorator
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
    withLogging("Clearing history") {
      all.forEach { item in
        if item.isUnpinned {
          cleanup(item)
        }
      }
      all.removeAll(where: \.isUnpinned)
      sessionLog.removeValues { $0.pin == nil }
      items = all

      do {
        try Storage.shared.context.transaction {
          try Storage.shared.context.delete(
            model: HistoryItem.self,
            where: #Predicate { $0.pin == nil }
          )
        }
        Storage.shared.context.processPendingChanges()
        try Storage.shared.context.save()

        // Re-fetch remaining (pinned) items using a fresh context to avoid stale references
        let freshContext = ModelContext(Storage.shared.container)
        let pinnedDescriptor = FetchDescriptor<HistoryItem>(predicate: #Predicate { $0.pin != nil })
        let pinnedResults = (try? freshContext.fetch(pinnedDescriptor)) ?? []
        let refreshedPinned = sorter.sort(pinnedResults).map { HistoryItemDecorator($0) }
        all = refreshedPinned
        items = all
      } catch {
        logger.error("Failed to clear history: \(error.localizedDescription)")
        return
      }
    }

    // Update pagination manager total count
    if Defaults[.isUnlimitedHistory] {
      let countDescriptor = FetchDescriptor<HistoryItem>()
      let count = (try? Storage.shared.context.fetchCount(countDescriptor)) ?? 0
      paginationManager.updateTotalCount(count)
    }

    Clipboard.shared.clear()
    AppState.shared.popup.close()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func clearAll() {
    withLogging("Clearing all history") {
      all.forEach { item in
        cleanup(item)
      }
      all.removeAll()
      sessionLog.removeAll()
      items = all

      do {
        try Storage.shared.context.transaction {
          try Storage.shared.context.delete(model: HistoryItem.self)
        }
        Storage.shared.context.processPendingChanges()
        try Storage.shared.context.save()

        // Rebuild arrays using a fresh context to avoid stale references
        let freshContext = ModelContext(Storage.shared.container)
        let pinnedDescriptor = FetchDescriptor<HistoryItem>(predicate: #Predicate { $0.pin != nil })
        let pinnedResults = (try? freshContext.fetch(pinnedDescriptor)) ?? []
        let refreshedPinned = sorter.sort(pinnedResults).map { HistoryItemDecorator($0) }
        all = refreshedPinned
        items = all
      } catch {
        logger.error("Failed to clear all history: \(error.localizedDescription)")
        return
      }
    }

    // Update pagination manager total count
    if Defaults[.isUnlimitedHistory] {
      paginationManager.updateTotalCount(0)
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
      Storage.shared.context.delete(item.item)
      Storage.shared.context.processPendingChanges()
      try? Storage.shared.context.save()
    }

    if Defaults[.isUnlimitedHistory] {
      paginationManager.handleItemRemoved(item)
      all = paginationManager.allLoadedItems
    } else {
      all.removeAll { $0 == item }
    }
    items.removeAll { $0 == item }
    sessionLog.removeValues { $0 == item.item }

    updateUnpinnedShortcuts()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  private func cleanup(_ item: HistoryItemDecorator) {
    item.cleanupImages()
  }

  private func currentModifierFlags() -> NSEvent.ModifierFlags {
    return NSApp.currentEvent?.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function]) ?? []
  }

  @MainActor
  func select(_ item: HistoryItemDecorator?) {
    guard let item else {
      return
    }

    let modifierFlags = currentModifierFlags()

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

    // Ensure we properly handle this item in subsequent operations
    Task { @MainActor in
      let currentChangeCount = Clipboard.shared.changeCount
      if let existing = sessionLog[currentChangeCount], existing.secret != item.item.secret {
        existing.secret = item.item.secret
      }
    }

    Task {
      searchQuery = ""
    }
  }

  @MainActor
  func startPasteStack(selection: inout Selection<HistoryItemDecorator>) {
    guard let item = selection.first else { return }
    PasteStack.initializeIfNeeded()

    let modifierFlags = currentModifierFlags()

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
  func toggleSecret(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    item.toggleSecret()

    // Update the item title display immediately
    if let index = items.firstIndex(of: item) {
      items[index] = item
    }

    if let index = all.firstIndex(of: item) {
      all[index] = item
    }

    // If we're viewing the item, the UI will reflect changes via navigator selection.
    // No direct selection state is managed in History.
  }

  @MainActor
  private func findSimilarItem(_ item: HistoryItem) -> HistoryItem? {
    // Prefer fast path using textDigest to narrow candidates
    if let text = item.text, !text.isEmpty {
      let digest = HistoryItem.makeTextDigest(text)
      let descriptor = FetchDescriptor<HistoryItem>(predicate: #Predicate { $0.textDigest == digest })
      if let candidates = try? Storage.shared.context.fetch(descriptor) {
        let duplicates = candidates.filter({ $0 == item || $0.supersedes(item) })
        if duplicates.count > 1 { return duplicates.first(where: { $0 != item }) }
        if let modified = isModified(item) { return modified }
        return duplicates.first
      }
    }

    // Fallback: fetch all if no text or digest
    let descriptor = FetchDescriptor<HistoryItem>()
    guard let all = try? Storage.shared.context.fetch(descriptor) else {
      return nil
    }

    let duplicates = all.filter({ $0 == item || $0.supersedes(item) })
    if duplicates.count > 1 {
      return duplicates.first(where: { $0 != item })
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

  // MARK: - Batched insert support
  @MainActor
  private func enqueueInsert(_ item: HistoryItem) {
    pendingInserts.append(item)
    scheduleBatchedSave()
  }
  @MainActor
  private func scheduleBatchedSave() {
    saveWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      do {
        for item in self.pendingInserts {
          Storage.shared.context.insert(item)
        }
        self.pendingInserts.removeAll()
        Storage.shared.context.processPendingChanges()
        try Storage.shared.context.save()
      } catch {
        self.logger.error("Batched save failed: \(error.localizedDescription)")
      }
    }
    saveWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
  }
}

