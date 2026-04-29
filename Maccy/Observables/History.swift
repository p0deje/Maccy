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

  var searchQuery: String = "" {
    didSet {
      searchRevision += 1
      let query = searchQuery
      let revision = searchRevision
      searchTask?.cancel()
      searchTask = nil
      if query.isEmpty {
        Task { @MainActor in
          startThumbnailBackfillIfNeeded()
        }
      } else {
        Task { @MainActor in
          await stopThumbnailBackfill()
        }
      }
      throttler.throttle { [self] in
        guard revision == searchRevision else { return }

        if query.isEmpty {
          // Restore the paginated browse view.
          updateItems(all.map { Search.SearchResult(object: $0) })
          AppState.shared.navigator.select(item: unpinnedItems.first)
          AppState.shared.popup.needsResize = true
        } else {
          // Show matches from the retained window immediately so typing does
          // not feel blocked by the full-history fetch below.
          updateItems(search.search(string: query, within: all))
          AppState.shared.navigator.highlightFirst()
          AppState.shared.popup.needsResize = true

          // Search needs to span ALL items, not just the loaded page.
          // Fetch the rest in the background, then replace results only if
          // this query is still current.
          searchTask = Task { @MainActor in
            defer {
              if revision == searchRevision {
                searchTask = nil
              }
            }
            let searchItems = await fullHistoryDecoratorsForSearch()
            guard !Task.isCancelled else { return }
            guard revision == searchRevision, searchQuery == query else { return }
            await updateItems(search.search(string: query, within: searchItems), query: query)
            AppState.shared.navigator.highlightFirst()
            AppState.shared.popup.needsResize = true
          }
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

  private let search = Search()
  private let sorter = Sorter()
  private let throttler = Throttler(minimumDelay: 0.2)
  @ObservationIgnored
  private var searchRevision = 0
  @ObservationIgnored
  private var searchTask: Task<Void, Never>?

  @ObservationIgnored
  private var sessionLog: [Int: HistoryItem] = [:]

  // The distinction between `all` and `items` is the following:
  // - `all` stores all history items, even the ones that are currently hidden by a search
  // - `items` stores only visible history items, updated during a search
  @ObservationIgnored
  var all: [HistoryItemDecorator] = []

  // Soft flush: drop decorators + reset SwiftData context after the popup
  // has been closed for a while so the OS can release blob memory loaded
  // during browsing/preview. Re-fetched on demand by `load()`.
  @ObservationIgnored
  private var idleFlushTask: Task<Void, Never>?
  private static let idleFlushDelay: Duration = .seconds(60)
  @ObservationIgnored
  private(set) var needsReloadAfterIdleFlush = false

  // Background thumbnail backfill — only runs while the popup is open.
  @ObservationIgnored
  private var backfillTask: Task<Void, Never>?

  // Pagination: only the first `pageSize` unpinned items are loaded into
  // memory at startup. More are fetched on demand as the user scrolls near
  // the end. Pinned items are always all loaded (small set, capped by the
  // pin-shortcut alphabet at ~22).
  private static let pageSize = 50
  private static let maxUnpinnedWindowSize = 3000
  private static let pruneUnpinnedBatchSize = 50
  // Trigger loadMore when this many items from the end becomes visible.
  private static let pageLoadAheadCount = 20
  @ObservationIgnored
  private var hasMoreUnpinnedItems = false
  @ObservationIgnored
  private var isLoadingMore = false
  // True once we've fetched everything (only happens when search forces a
  // full load, or pagination reaches the end naturally).
  @ObservationIgnored
  private var allUnpinnedFetched = false
  // Cached counts so `itemDidAppear` and `appendUnpinned` don't have to
  // rescan `all` (which is O(n) and gets called on every scroll event).
  @ObservationIgnored
  private var loadedPinnedCount = 0
  @ObservationIgnored
  private var loadedUnpinnedCount = 0
  @ObservationIgnored
  private var loadedUnpinnedStartIndex = 0
  @ObservationIgnored
  private var totalUnpinnedCount = 0

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
  func scheduleIdleFlush() {
    idleFlushTask?.cancel()
    idleFlushTask = Task { [weak self] in
      try? await Task.sleep(for: Self.idleFlushDelay)
      guard !Task.isCancelled else { return }
      await self?.flushIfIdle()
    }
  }

  @MainActor
  func cancelIdleFlush() {
    idleFlushTask?.cancel()
    idleFlushTask = nil
  }

  @MainActor
  private func flushIfIdle() async {
    guard AppState.shared.popup.isClosed() else {
      logger.info("Idle flush: skipped (popup still open)")
      return
    }
    guard pasteStack == nil else {
      logger.info("Idle flush: skipped (paste stack in progress)")
      return
    }
    guard !all.isEmpty else {
      logger.info("Idle flush: skipped (already empty)")
      return
    }

    let beforeCount = all.count
    logger.info("Idle flush: dropping \(beforeCount) decorators and resetting SwiftData context")

    // Cancel and AWAIT any in-flight backfill so its actor's context fully
    // releases before we recreate the container. Without the await, the
    // backfill could be mid-sleep and still pinning blob memory.
    await stopThumbnailBackfill()

    AppState.shared.navigator.selectWithoutScrolling(item: nil)
    items = []
    all = []
    sessionLog = [:]
    // Drop every cached app icon + its file watcher. Saves ~30-60 MB
    // depending on how many distinct source apps the session touched.
    ApplicationImageCache.shared.clear()

    Storage.shared.recreateContainer()
    needsReloadAfterIdleFlush = true
    logger.info("Idle flush: complete, decorators will reload on next popup open")
  }

  @MainActor
  func load() async throws {
    needsReloadAfterIdleFlush = false
    // Pinned items: always load all (small set, max ~22 due to single-letter shortcuts).
    var pinnedDescriptor = FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.pin != nil },
      sortBy: sortDescriptors()
    )
    pinnedDescriptor.fetchLimit = 64
    let pinnedItems = (try? Storage.shared.context.fetch(pinnedDescriptor)) ?? []

    // Unpinned items: just the first page.
    var unpinnedDescriptor = FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.pin == nil },
      sortBy: sortDescriptors()
    )
    unpinnedDescriptor.fetchLimit = Self.pageSize
    let unpinnedResults = (try? Storage.shared.context.fetch(unpinnedDescriptor)) ?? []

    let pinnedDecorators = pinnedItems.map { HistoryItemDecorator($0) }
    let unpinnedDecorators = unpinnedResults.map { HistoryItemDecorator($0) }
    all = combineDecorators(pinned: pinnedDecorators, unpinned: unpinnedDecorators)
    items = all
    loadedPinnedCount = pinnedDecorators.count
    loadedUnpinnedCount = unpinnedDecorators.count
    loadedUnpinnedStartIndex = 0
    let countDescriptor = FetchDescriptor<HistoryItem>(predicate: #Predicate { $0.pin == nil })
    totalUnpinnedCount = (try? Storage.shared.context.fetchCount(countDescriptor)) ?? unpinnedResults.count
    updatePaginationFlags()

    limitHistorySize(to: Defaults[.size])

    updateShortcuts()
    // Ensure that panel size is proper *after* loading all items.
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func loadForPopupOpenIfNeeded() async {
    guard all.isEmpty || needsReloadAfterIdleFlush else { return }

    try? await load()
    guard !searchQuery.isEmpty else { return }

    let query = searchQuery
    let revision = searchRevision
    let searchItems = await fullHistoryDecoratorsForSearch()
    guard !Task.isCancelled, revision == searchRevision, searchQuery == query else { return }
    await updateItems(search.search(string: query, within: searchItems), query: query)
    AppState.shared.navigator.highlightFirst()
    AppState.shared.popup.needsResize = true
  }

  // SortDescriptor matching the user's `Defaults[.sortBy]` choice. Used by
  // every paginated fetch so SQLite returns rows in the right order without
  // us having to materialize and re-sort.
  private func sortDescriptors() -> [SortDescriptor<HistoryItem>] {
    switch Defaults[.sortBy] {
    case .firstCopiedAt:
      return [SortDescriptor(\.firstCopiedAt, order: .reverse)]
    case .numberOfCopies:
      return [SortDescriptor(\.numberOfCopies, order: .reverse)]
    default:
      return [SortDescriptor(\.lastCopiedAt, order: .reverse)]
    }
  }

  // Pinned-vs-unpinned ordering matches `Defaults[.pinTo]`; within each
  // group the SQL fetch already gave us the right primary sort.
  private func combineDecorators(
    pinned: [HistoryItemDecorator],
    unpinned: [HistoryItemDecorator]
  ) -> [HistoryItemDecorator] {
    if Defaults[.pinTo] == .bottom {
      return unpinned + pinned
    } else {
      return pinned + unpinned
    }
  }

  // Called from `HistoryItemView.onAppear` with the row's index in
  // `unpinnedItems`. O(1) — no array filter, no search. Fast enough to fire
  // on every scrolling row without affecting frame rate.
  @MainActor
  func itemDidAppear(at unpinnedIndex: Int) {
    guard searchQuery.isEmpty else { return }
    guard !isLoadingMore else { return }

    let absoluteIndex = loadedUnpinnedStartIndex + unpinnedIndex
    let loadedEndIndex = loadedUnpinnedStartIndex + loadedUnpinnedCount

    if loadedUnpinnedStartIndex > 0,
       unpinnedIndex <= Self.pageLoadAheadCount {
      Task { @MainActor in
        await loadPreviousUnpinnedItems()
      }
      return
    }

    guard hasMoreUnpinnedItems else { return }
    guard absoluteIndex >= loadedEndIndex - Self.pageLoadAheadCount else { return }
    Task { @MainActor in
      await loadMoreUnpinnedItems()
    }
  }

  @MainActor
  private func loadMoreUnpinnedItems() async {
    guard hasMoreUnpinnedItems, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }

    var descriptor = FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.pin == nil },
      sortBy: sortDescriptors()
    )
    descriptor.fetchOffset = loadedUnpinnedStartIndex + loadedUnpinnedCount
    descriptor.fetchLimit = Self.pageSize

    guard let next = try? Storage.shared.context.fetch(descriptor), !next.isEmpty else {
      hasMoreUnpinnedItems = false
      allUnpinnedFetched = true
      return
    }

    // Build decorators in chunks with yields so SwiftUI can update scroll
    // position between batches instead of stalling on the whole page.
    var newDecorators: [HistoryItemDecorator] = []
    newDecorators.reserveCapacity(next.count)
    for (idx, item) in next.enumerated() {
      newDecorators.append(HistoryItemDecorator(item))
      if idx > 0 && idx % 25 == 0 {
        await Task.yield()
      }
    }
    appendUnpinned(newDecorators)
    pruneUnpinnedWindowIfNeeded(fromTop: true)
    updatePaginationFlags()
  }

  @MainActor
  private func loadPreviousUnpinnedItems() async {
    guard loadedUnpinnedStartIndex > 0, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }

    let offset = max(0, loadedUnpinnedStartIndex - Self.pageSize)
    let limit = loadedUnpinnedStartIndex - offset

    var descriptor = FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.pin == nil },
      sortBy: sortDescriptors()
    )
    descriptor.fetchOffset = offset
    descriptor.fetchLimit = limit

    guard let previous = try? Storage.shared.context.fetch(descriptor), !previous.isEmpty else {
      loadedUnpinnedStartIndex = 0
      updatePaginationFlags()
      return
    }

    var newDecorators: [HistoryItemDecorator] = []
    newDecorators.reserveCapacity(previous.count)
    for (idx, item) in previous.enumerated() {
      newDecorators.append(HistoryItemDecorator(item))
      if idx > 0 && idx % 25 == 0 {
        await Task.yield()
      }
    }
    prependUnpinned(newDecorators)
    loadedUnpinnedStartIndex = offset
    pruneUnpinnedWindowIfNeeded(fromTop: false)
    updatePaginationFlags()
  }

  // For use by the search path: load a temporary full-history corpus so search
  // can match outside the current paginated browse window without replacing it.
  @MainActor
  private func fullHistoryDecoratorsForSearch() async -> [HistoryItemDecorator] {
    let container = Storage.shared.container
    let sortBy = Defaults[.sortBy]
    let pinTo = Defaults[.pinTo]
    let ids = await SearchHistoryLoader(modelContainer: container)
      .sortedItemIDs(sortBy: sortBy, pinTo: pinTo)
    guard !Task.isCancelled, !ids.isEmpty else { return [] }

    return await decorators(from: ids)
  }

  @MainActor
  private func decorators(from results: [HistoryItem]) async -> [HistoryItemDecorator] {
    var decorators: [HistoryItemDecorator] = []
    decorators.reserveCapacity(results.count)
    for (idx, item) in results.enumerated() {
      decorators.append(HistoryItemDecorator(item))
      if idx > 0 && idx % 100 == 0 {
        await Task.yield()
      }
    }
    return decorators
  }

  @MainActor
  private func decorators(from ids: [PersistentIdentifier]) async -> [HistoryItemDecorator] {
    var decorators: [HistoryItemDecorator] = []
    decorators.reserveCapacity(ids.count)

    for (idx, id) in ids.enumerated() {
      guard !Task.isCancelled else { break }
      if let item = Storage.shared.context.model(for: id) as? HistoryItem {
        decorators.append(HistoryItemDecorator(item))
      }
      if idx > 0 && idx % 50 == 0 {
        await Task.yield()
      }
    }

    return decorators
  }

  @MainActor
  private func appendUnpinned(_ newDecorators: [HistoryItemDecorator]) {
    // Direct O(k) insert — no full array filtering. New unpinned rows always
    // go after the existing unpinned section, so the position depends only
    // on `pinTo` and our cached counts.
    if Defaults[.pinTo] == .bottom {
      // Layout: [unpinned... | pinned...]. Insert at end of unpinned section.
      all.insert(contentsOf: newDecorators, at: loadedUnpinnedCount)
    } else {
      // Layout: [pinned... | unpinned...]. Append to the end.
      all.append(contentsOf: newDecorators)
    }
    loadedUnpinnedCount += newDecorators.count

    if searchQuery.isEmpty {
      items = all
    }
    // Skip `updateUnpinnedShortcuts` — the shortcut-eligible rows (first 9
    // unpinned) didn't change, only items further down were appended.
  }

  @MainActor
  private func prependUnpinned(_ newDecorators: [HistoryItemDecorator]) {
    if Defaults[.pinTo] == .bottom {
      all.insert(contentsOf: newDecorators, at: 0)
    } else {
      all.insert(contentsOf: newDecorators, at: loadedPinnedCount)
    }
    loadedUnpinnedCount += newDecorators.count

    if searchQuery.isEmpty {
      items = all
    }
  }

  @MainActor
  private func pruneUnpinnedWindowIfNeeded(fromTop: Bool) {
    guard searchQuery.isEmpty else { return }
    guard loadedUnpinnedCount > Self.maxUnpinnedWindowSize else { return }

    let pruneCount = min(
      Self.pruneUnpinnedBatchSize,
      loadedUnpinnedCount - Self.pageSize
    )
    guard pruneCount > 0 else { return }

    let removeRange: Range<Int>
    if fromTop {
      if Defaults[.pinTo] == .bottom {
        removeRange = 0..<pruneCount
      } else {
        removeRange = loadedPinnedCount..<(loadedPinnedCount + pruneCount)
      }
    } else {
      if Defaults[.pinTo] == .bottom {
        let start = loadedUnpinnedCount - pruneCount
        removeRange = start..<(start + pruneCount)
      } else {
        let start = loadedPinnedCount + loadedUnpinnedCount - pruneCount
        removeRange = start..<(start + pruneCount)
      }
    }

    let pruned = Array(all[removeRange])
    for item in pruned {
      cleanup(item)
    }

    let selectedPruned = pruned.contains { prunedItem in
      AppState.shared.navigator.selection.first(where: { selected in
        selected == prunedItem
      }) != nil
    }
    if selectedPruned {
      AppState.shared.navigator.selection = Selection()
    }

    all.removeSubrange(removeRange)
    if fromTop {
      loadedUnpinnedStartIndex += pruneCount
    }
    loadedUnpinnedCount -= pruneCount

    if searchQuery.isEmpty {
      items = all
    }
  }

  private func updatePaginationFlags() {
    let loadedEndIndex = loadedUnpinnedStartIndex + loadedUnpinnedCount
    hasMoreUnpinnedItems = loadedEndIndex < totalUnpinnedCount
    allUnpinnedFetched = loadedUnpinnedStartIndex == 0 && loadedEndIndex >= totalUnpinnedCount
  }

  // Backfill is gated on popup state: only runs while the user has the popup
  // open. That way idle memory stays low — the moment the popup closes,
  // backfill stops and `flushIfIdle` can release everything cleanly.
  @MainActor
  func startThumbnailBackfillIfNeeded() {
    guard backfillTask == nil else { return }
    let container = Storage.shared.container
    backfillTask = Task.detached(priority: .background) {
      while !Task.isCancelled {
        // Scoped block — actor + its context die when this exits, so the
        // batch's hydrated `contents` blobs drop between batches.
        let count = await {
          let actor = ThumbnailBackfiller(modelContainer: container)
          return await actor.backfillBatch(limit: 10)
        }()
        if count == 0 { break }
        try? await Task.sleep(for: .milliseconds(1500))
      }
    }
  }

  @MainActor
  func stopThumbnailBackfill() async {
    guard let task = backfillTask else { return }
    task.cancel()
    _ = await task.value
    backfillTask = nil
  }

  @MainActor
  private func limitHistorySize(to maxSize: Int) {
    // DB-based now: `all` may only hold the first page of unpinned items,
    // so filtering it locally would never trigger a prune for paginated
    // installs. Fetch the count from SQLite and delete the oldest excess.
    let countDescriptor = FetchDescriptor<HistoryItem>(predicate: #Predicate { $0.pin == nil })
    guard let count = try? Storage.shared.context.fetchCount(countDescriptor),
          count > maxSize else {
      return
    }

    var descriptor = FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.pin == nil },
      sortBy: [SortDescriptor(\.lastCopiedAt)]  // ascending: oldest first
    )
    descriptor.fetchLimit = count - maxSize
    guard let toDelete = try? Storage.shared.context.fetch(descriptor) else { return }

    for stale in toDelete {
      // Drop in-memory references too if they happen to be on the loaded page.
      all.removeAll { $0.item == stale }
      items.removeAll { $0.item == stale }
      Storage.shared.context.delete(stale)
    }
    Storage.shared.context.processPendingChanges()
    try? Storage.shared.context.save()
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

    var removedItemIndex: Int?
    if let existingHistoryItem = findSimilarItem(item) {
      if isModified(item) == nil {
        item.contents = existingHistoryItem.contents
        item.contentFingerprint = existingHistoryItem.contentFingerprint
        item.thumbnailData = existingHistoryItem.thumbnailData
      }
      item.firstCopiedAt = existingHistoryItem.firstCopiedAt
      item.numberOfCopies += existingHistoryItem.numberOfCopies
      item.pin = existingHistoryItem.pin
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
    limitHistorySize(to: Defaults[.size] - 1)

    sessionLog[Clipboard.shared.changeCount] = item

    var itemDecorator: HistoryItemDecorator
    if let pin = item.pin {
      itemDecorator = HistoryItemDecorator(item, shortcuts: KeyShortcut.create(character: pin))
      // Keep pins in the same place.
      if let removedItemIndex {
        all.insert(itemDecorator, at: removedItemIndex)
      }
    } else {
      itemDecorator = HistoryItemDecorator(item)

      let sortedItems = sorter.sort(all.map(\.item) + [item])
      if let index = sortedItems.firstIndex(of: item) {
        all.insert(itemDecorator, at: index)
      }

      items = all
      updateUnpinnedShortcuts()
      AppState.shared.popup.needsResize = true
    }

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
    withLogging("Clearing all history") {
      all.forEach { item in
        cleanup(item)
      }
      all.removeAll()
      sessionLog.removeAll()
      items = all

      try? Storage.shared.context.delete(model: HistoryItem.self)
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
      Storage.shared.context.delete(item.item)
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

    Task {
      searchQuery = ""
    }
  }

  @MainActor
  func startPasteStack(selection: inout Selection<HistoryItemDecorator>) {
    guard AppState.shared.multiSelectionEnabled else { return }
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
  private func findSimilarItem(_ item: HistoryItem) -> HistoryItem? {
    if let modifiedItem = isModified(item) {
      return modifiedItem
    }

    item.ensureContentFingerprint()

    if let fingerprint = item.contentFingerprint {
      var fingerprintDescriptor = FetchDescriptor<HistoryItem>(
        predicate: #Predicate { $0.contentFingerprint == fingerprint },
        sortBy: sortDescriptors()
      )
      fingerprintDescriptor.fetchLimit = 2

      if let duplicate = try? Storage.shared.context.fetch(fingerprintDescriptor)
        .first(where: { $0 != item }) {
        return duplicate
      }
    }

    return nil
  }

  private func isModified(_ item: HistoryItem) -> HistoryItem? {
    if let modified = item.modified, sessionLog.keys.contains(modified) {
      return sessionLog[modified]
    }

    return nil
  }

  private func updateItems(_ newItems: [Search.SearchResult], query: String? = nil) {
    let query = query ?? searchQuery
    items = newItems.map { result in
      let item = result.object
      item.highlight(query, result.ranges)

      return item
    }

    updateUnpinnedShortcuts()
  }

  @MainActor
  private func updateItems(_ newItems: [Search.SearchResult], query: String) async {
    var updatedItems: [HistoryItemDecorator] = []
    updatedItems.reserveCapacity(newItems.count)

    for (idx, result) in newItems.enumerated() {
      let item = result.object
      item.highlight(query, result.ranges)
      updatedItems.append(item)

      if idx > 0 && idx % 100 == 0 {
        await Task.yield()
      }
    }

    items = updatedItems
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
