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

  var pasteStack: PasteStack?

  var items: ConcatenatedCollection<HistoryItemDecorator> {
    switch Defaults[.pinTo] {
    case .top:
      ConcatenatedCollection(pinnedItems, unpinnedItems)
    case .bottom:
      ConcatenatedCollection(unpinnedItems, pinnedItems)
    }
  }
  var pinnedItems: [HistoryItemDecorator] {
    searchQuery.isEmpty ? allPinnedItems : filteredPinnedItems
  }
  var unpinnedItems: [HistoryItemDecorator] {
    searchQuery.isEmpty ? allUnpinnedItems : filteredUnpinnedItems
  }
  var availablePins: [String] { pinManager.availablePins }

  var firstPinnedItem: HistoryItemDecorator? { pinnedItems.first }
  var firstUnpinnedItem: HistoryItemDecorator? { unpinnedItems.first }

  var searchQuery: String = "" {
    didSet(previousSearchQuery) {
      guard searchQuery != previousSearchQuery else { return }
      throttler.throttle { [self] in
        updateSearchResults()

        if searchQuery.isEmpty {
          AppState.shared.navigator.select(item: firstUnpinnedItem)
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
  private let pinManager = PinManager()
  private var allPinnedItems: [HistoryItemDecorator] { pinManager.pinnedItems }
  private var allUnpinnedItems: [HistoryItemDecorator] = []
  private var filteredPinnedItems: [HistoryItemDecorator] = []
  private var filteredUnpinnedItems: [HistoryItemDecorator] = []

  @ObservationIgnored
  private var sessionLog: [Int: HistoryItem] = [:]

  // Pagination support for unlimited history
  @ObservationIgnored
  private let paginationManager = PaginationManager(source: HistoryPaginationSource())
  private var paginationSource: HistoryPaginationSource { paginationManager.source }

  /// Maximum number of search results in unlimited mode. Results are in sort
  /// order, so these are the most relevant matches by the current sorting.
  private static let unlimitedSearchLimit = 1_000

  /// Total number of items in storage, including the ones not paged in.
  var totalCount: Int {
    allPinnedItems.count + unpinnedTotalCount
  }

  /// Total number of unpinned items in storage (the rows of the virtualized list).
  var unpinnedTotalCount: Int {
    Defaults[.isUnlimitedHistory] ? paginationManager.totalCount : allUnpinnedItems.count
  }

  /// Number of unpinned items that a history size limit of `size` deletes.
  func itemsDeletedByLimit(_ size: Int) -> Int {
    max(0, unpinnedTotalCount - size)
  }

  /// Rows of the virtualized list currently backed by loaded items.
  var loadedRange: Range<Int> {
    paginationManager.loadedRange
  }

  /// Sorted indices of unpinned rows that render at the tall (image) height.
  var tallRowIndices: [Int] {
    paginationManager.tallRowIndices
  }

#if DEBUG
  static let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
#endif

  init() {
    #if DEBUG
    guard !Self.isRunningUnitTests else { return }
    #endif

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
        updateTitlesForSpecialSymbols()
      }
    }

    Task {
      for await _ in Defaults.updates(.imageMaxHeight, initial: false) {
        for item in items {
          item.cleanupImages()
        }
      }
    }

    Task {
      for await _ in Defaults.updates(.isUnlimitedHistory, initial: false) {
        // Reload history when switching between limited and unlimited modes.
        try? await load()
      }
    }
  }

  @MainActor
  func load() async throws {
    if Defaults[.isUnlimitedHistory] {
      // Pinned items are always fully loaded; unpinned items are paged in on demand.
      let descriptor = FetchDescriptor<HistoryItem>(predicate: #Predicate { $0.pin != nil })
      let results = try Storage.shared.context.fetch(descriptor)
      pinManager.load(from: results.map { HistoryItemDecorator($0) })
      paginationSource.invalidate()
      do {
        try paginationManager.load()
      } catch {
        // Callers discard this error, so record it before rethrowing.
        logger.error("Failed to load paginated history: \(error.localizedDescription)")
        throw error
      }
      allUnpinnedItems = paginationManager.loadedItems
    } else {
      let descriptor = FetchDescriptor<HistoryItem>()
      let results = try Storage.shared.context.fetch(descriptor)
      let decorators = sorter.sort(results).map { HistoryItemDecorator($0) }
      pinManager.load(from: decorators)
      allUnpinnedItems = decorators.filter(\.isUnpinned)
    }
    filteredPinnedItems = allPinnedItems
    filteredUnpinnedItems = allUnpinnedItems

    limitHistorySize(to: Defaults[.size])

    updateShortcuts()
    // Ensure that panel size is proper *after* loading all items.
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  /// Make sure the items backing the given rows of the virtualized list are
  /// loaded. Called by the list whenever the set of visible rows changes.
  @MainActor
  func ensureLoaded(rows: Range<Int>) {
    guard Defaults[.isUnlimitedHistory] else { return }

    let loadedBefore = paginationManager.loadedRange
    do {
      try paginationManager.ensureRowsLoaded(rows)
    } catch {
      logger.error("Failed to load history rows \(rows): \(error.localizedDescription)")
    }

    if paginationManager.loadedRange != loadedBefore {
      allUnpinnedItems = paginationManager.loadedItems
      if searchQuery.isEmpty {
        updateUnpinnedShortcuts()
      }
    }
  }

  /// Refetch the pagination window after storage changed, so that the
  /// unpinned items reflect the current store and sort order. Callers update
  /// the pagination source first, or invalidate it.
  @MainActor
  private func refreshPagination() {
    do {
      try paginationManager.refresh()
    } catch {
      logger.error("Failed to refresh paginated history: \(error.localizedDescription)")
    }
    allUnpinnedItems = paginationManager.loadedItems
  }

  @MainActor
  private func limitHistorySize(to maxSize: Int) {
    guard !Defaults[.isUnlimitedHistory] else { return }

    if allUnpinnedItems.count >= maxSize {
      allUnpinnedItems[maxSize...].forEach(delete)
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
    if #available(macOS 15.0, *) {
      try? History.shared.insertIntoStorage(item)
    } else {
      // On macOS 14 the history item needs to be inserted into storage directly after creating it.
      // It was already inserted after creation in Clipboard.swift
    }

    var replacedPinnedItem: HistoryItemDecorator?
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
      if let existingDecorator = firstStoredItem(where: { $0.item == existingHistoryItem }) {
        cleanup(existingDecorator)
        allUnpinnedItems.removeAll { $0 == existingDecorator }
        if existingDecorator.isPinned {
          replacedPinnedItem = existingDecorator
        }
      }
      deleteFromStorage(existingHistoryItem)
    } else {
      Task {
        Notifier.notify(body: item.title, sound: .write)
      }
    }

    // Remove exceeding items. Do this after the item is added to avoid removing something
    // if a duplicate was found as then the size already stayed the same.
    limitHistorySize(to: item.pin == nil ? Defaults[.size] - 1 : Defaults[.size])

    sessionLog[Clipboard.shared.changeCount] = item

    let itemDecorator: HistoryItemDecorator
    if let pin = item.pin {
      itemDecorator = HistoryItemDecorator(item, shortcuts: KeyShortcut.create(character: pin))
      if let replacedPinnedItem {
        pinManager.replace(replacedPinnedItem, with: itemDecorator)
      } else {
        pinManager.add(itemDecorator)
      }
    } else {
      itemDecorator = HistoryItemDecorator(item)
      insertUnpinned(itemDecorator)
    }

    if searchQuery.isEmpty {
      updateUnpinnedShortcuts()
    } else {
      updateSearchResults()
    }
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
      allUnpinnedItems.forEach(cleanup)
      allUnpinnedItems.removeAll()
      filteredUnpinnedItems.removeAll()
      sessionLog.removeValues { $0.pin == nil }

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

    if Defaults[.isUnlimitedHistory] {
      paginationSource.invalidate()
      refreshPagination()
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
      allPinnedItems.forEach(cleanup)
      allUnpinnedItems.forEach(cleanup)
      allUnpinnedItems.removeAll()
      filteredPinnedItems.removeAll()
      filteredUnpinnedItems.removeAll()
      pinManager.removeAll()
      sessionLog.removeAll()

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

    if Defaults[.isUnlimitedHistory] {
      paginationSource.invalidate()
      refreshPagination()
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

    // Read before deletion: the model's backing data is gone afterwards.
    let wasUnpinned = item.isUnpinned
    cleanup(item)
    withLogging("Removing history item") {
      deleteFromStorage(item.item)
      Storage.shared.context.processPendingChanges()
      try? Storage.shared.context.save()
    }

    pinManager.remove(item)
    allUnpinnedItems.removeAll { $0 == item }
    filteredPinnedItems.removeAll { $0 == item }
    filteredUnpinnedItems.removeAll { $0 == item }
    sessionLog.removeValues { $0 == item.item }

    if Defaults[.isUnlimitedHistory], wasUnpinned {
      refreshPagination()
    }

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
    if Defaults[.isUnlimitedHistory] {
      paginationSource.remove(item)
    }
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
        Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
      } else {
        switch HistoryItemAction(stack.modifierFlags) {
        case .copy:
          Clipboard.shared.copy(item.item)
        case .paste:
          Clipboard.shared.copy(item.item)
        case .pasteWithoutFormatting:
          Clipboard.shared.copy(item.item, removeFormatting: true)
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

    let wasPinned = item.isPinned
    pinManager.toggle(item)
    guard item.isPinned != wasPinned else { return }

    if wasPinned {
      insertUnpinned(item)
    } else {
      removeUnpinned(item)
    }

    searchQuery = ""
    updateUnpinnedShortcuts()
    if item.isUnpinned {
      AppState.shared.navigator.scrollTarget = item.id
    }
  }

  @MainActor
  func movePin(from source: IndexSet, to destination: Int) {
    guard searchQuery.isEmpty else { return }
    pinManager.move(from: source, to: destination)
  }

  @MainActor
  func updatePin(_ item: HistoryItem, to pin: String) {
    guard let itemDecorator = firstStoredItem(where: { $0.item.id == item.id }) else { return }

    let wasPinned = itemDecorator.isPinned
    pinManager.updatePin(of: itemDecorator, to: pin)
    if !wasPinned && itemDecorator.isPinned {
      removeUnpinned(itemDecorator)
    }
    updateShortcuts()
  }

  @MainActor
  private func findSimilarItem(_ item: HistoryItem) -> HistoryItem? {
    if let duplicate = firstStoredItem(where: { $0.item != item && $0.item.supersedes(item) }) {
      return duplicate.item
    }

    if Defaults[.isUnlimitedHistory], !item.title.isEmpty {
      // Most of an unlimited history is not loaded. Compare titles first, so
      // contents are only loaded for likely duplicates. Images get their
      // title later from text recognition, so only loaded ones are checked.
      let duplicate = try? paginationSource.firstItem { stored in
        stored !== item && stored.title == item.title && stored.supersedes(item)
      }
      if let duplicate {
        return duplicate
      }
    }

    return isModified(item)
  }

  private func isModified(_ item: HistoryItem) -> HistoryItem? {
    if let modified = item.modified, sessionLog.keys.contains(modified) {
      return sessionLog[modified]
    }

    return nil
  }

  private func updateSearchResults() {
    filteredPinnedItems = filteredItems(
      from: search.search(string: searchQuery, within: allPinnedItems)
    )
    filteredUnpinnedItems = filteredItems(
      from: search.search(string: searchQuery, within: searchableUnpinnedItems)
    )

    updateUnpinnedShortcuts()
  }

  /// Unpinned items that a search runs over. In unlimited mode most items are
  /// not loaded, so the candidates come from the whole store.
  @MainActor
  private var searchableUnpinnedItems: [HistoryItemDecorator] {
    guard Defaults[.isUnlimitedHistory], !searchQuery.isEmpty else {
      return allUnpinnedItems
    }

    do {
      if let titleFilter = search.titleFilter(for: searchQuery) {
        return try paginationSource.items(
          where: { titleFilter($0.title) },
          limit: Self.unlimitedSearchLimit
        )
      }
      // Fuzzy search is only enabled for small histories, so all items can be scored.
      return try paginationSource.items(where: { _ in true })
    } catch {
      logger.error("Failed to search history: \(error.localizedDescription)")
      return allUnpinnedItems
    }
  }

  private func filteredItems(from results: [Search.SearchResult]) -> [HistoryItemDecorator] {
    results.map { result in
      let item = result.object
      item.highlight(searchQuery, result.ranges)

      return item
    }
  }

  private func firstStoredItem(
    where predicate: (HistoryItemDecorator) -> Bool
  ) -> HistoryItemDecorator? {
    allPinnedItems.first(where: predicate) ?? allUnpinnedItems.first(where: predicate)
  }

  private func insertUnpinned(_ item: HistoryItemDecorator) {
    if Defaults[.isUnlimitedHistory] {
      // The item is already in storage; refetch the current window so it
      // shows up at the position dictated by the sort order.
      paginationSource.insert(item)
      refreshPagination()
      return
    }

    let sortedItems = sorter.sort(allUnpinnedItems.map(\.item) + [item.item])
    guard let index = sortedItems.firstIndex(of: item.item) else { return }
    allUnpinnedItems.insert(item, at: index)
  }

  private func removeUnpinned(_ item: HistoryItemDecorator) {
    if Defaults[.isUnlimitedHistory] {
      paginationSource.remove(item.item)
      refreshPagination()
    } else {
      allUnpinnedItems.removeAll { $0 == item }
    }
  }

  private func updateShortcuts() {
    for item in pinManager.pinnedItems {
      if let pin = item.item.pin {
        item.shortcuts = KeyShortcut.create(character: pin)
      }
    }

    updateUnpinnedShortcuts()
  }

  @MainActor
  private func updateTitlesForSpecialSymbols() {
    for item in items where item.item.imageData == nil {
      updateTitle(item: item, title: item.item.generateTitle())
    }
  }

  @MainActor
  private func updateTitle(item: HistoryItemDecorator, title: String) {
    item.title = title
    item.item.title = title
  }

  private func updateUnpinnedShortcuts() {
    let shortcutItems = unpinnedItems.filter(\.isVisible)
    for item in shortcutItems {
      item.shortcuts = []
    }

    // Numeric shortcuts belong to the first rows. In unlimited mode those are
    // only loaded while the window starts at the top of the history.
    if Defaults[.isUnlimitedHistory], searchQuery.isEmpty, paginationManager.windowStartIndex > 0 {
      return
    }

    var index = 1
    for item in shortcutItems.prefix(9) {
      item.shortcuts = KeyShortcut.create(character: String(index))
      index += 1
    }
  }
}
