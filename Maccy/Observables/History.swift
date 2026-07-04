import AppKit.NSRunningApplication
import Defaults
import Foundation
import Logging
import Observation
import Sauce
import Settings
import SwiftData

/// Persistence operations `History` relies on, isolated to `@MainActor`.
protocol HistoryPersistence {
  @MainActor
  func insert(_ item: HistoryItem) throws
  @MainActor
  func delete(_ item: HistoryItem) throws
  @MainActor
  func deleteUnpinned() throws
  @MainActor
  func deleteAll() throws
  @MainActor
  func save() throws
  @MainActor
  func fetchAll() throws -> [HistoryItem]
  @MainActor
  func countHistoryItems() throws -> Int
  @MainActor
  func countHistoryItemContents() throws -> Int
}

/// `HistoryPersistence` backed by `Storage.shared.context` (the main SwiftData
/// context). Each mutating method processes pending changes and saves.
struct SwiftDataHistoryPersistence: HistoryPersistence {
  @MainActor
  func insert(_ item: HistoryItem) throws {
    Storage.shared.context.insert(item)
    Storage.shared.context.processPendingChanges()
    try Storage.shared.context.save()
  }

  @MainActor
  func delete(_ item: HistoryItem) throws {
    Storage.shared.context.delete(item)
    Storage.shared.context.processPendingChanges()
    try Storage.shared.context.save()
  }

  @MainActor
  func deleteUnpinned() throws {
    try Storage.shared.context.transaction {
      try Storage.shared.context.delete(
        model: HistoryItem.self,
        where: #Predicate { $0.pin == nil }
      )
      try Storage.shared.context.delete(
        model: HistoryItemContent.self,
        where: #Predicate { $0.item?.pin == nil }
      )
    }
    Storage.shared.context.processPendingChanges()
    try Storage.shared.context.save()
  }

  @MainActor
  func deleteAll() throws {
    try Storage.shared.context.delete(model: HistoryItem.self)
    Storage.shared.context.processPendingChanges()
    try Storage.shared.context.save()
  }

  @MainActor
  func save() throws {
    Storage.shared.context.processPendingChanges()
    try Storage.shared.context.save()
  }

  @MainActor
  func fetchAll() throws -> [HistoryItem] {
    try Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
  }

  @MainActor
  func countHistoryItems() throws -> Int {
    try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItem>())
  }

  @MainActor
  func countHistoryItemContents() throws -> Int {
    try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItemContent>())
  }
}

/// The main-actor clipboard history model: the in-memory `items`/`all` lists of
/// `HistoryItemDecorator`, persistence, search, pin/delete/clear actions, and
/// reconciliation of `StoreEvent`s emitted by the off-main ingest actor.
@MainActor
@Observable
class History: ItemsContainer {
  static let shared = History()
  let logger = Logger(label: "org.p0deje.Maccy")

  var items: [HistoryItemDecorator] = []
  var pasteStack: PasteStack?
  var lastPersistError: Error?

  /// Pinned decorators only.
  var pinnedItems: [HistoryItemDecorator] { items.filter(\.isPinned) }
  /// Unpinned decorators only.
  var unpinnedItems: [HistoryItemDecorator] { items.filter(\.isUnpinned) }

  /// The current search text; each change throttles `performSearch`.
  var searchQuery: String = "" {
    didSet {
      throttler.throttle { [self] in
        self.performSearch()
      }
    }
  }

  /// Re-runs the active search immediately after the configured search mode
  /// (`Defaults[.searchMode]`) changes — from either the search-field mode
  /// button or the Settings picker. No-op when the query is empty (nothing to
  /// refresh). Unlike keystrokes, this is a discrete action and skips the
  /// throttler.
  func refreshForModeChange() {
    guard !searchQuery.isEmpty else { return }
    performSearch()
  }

  /// Awaits the in-flight search task, if any, so a search-then-assert
  /// sequence is deterministic. No-op when no search is running.
  func waitForInFlightSearch() async {
    await searchTask?.value
  }

  /// The decorator whose keyboard shortcut matches the current event, if any.
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
  /// The single staleness oracle for off-main search. Every synchronous
  /// mutation of `items` (a newer keystroke's kickoff, an ingest re-filter,
  /// clear/clearAll/delete, the empty short-circuit) bumps it, so a late
  /// off-main apply whose captured generation no longer matches is discarded.
  /// All access is `@MainActor` (`History` is `@MainActor`) — plain `Int`, no
  /// lock, no `@unchecked`.
  @ObservationIgnored private(set) var searchGeneration = 0
  @ObservationIgnored private var searchTask: Task<Void, Never>?
  /// Owns the four-mode match off-main. A `let` actor (Sendable); only its
  /// `search(...)` method is awaited — the `@Model` never crosses to it, only
  /// Sendable DTOs.
  private let searchActor = SearchActor()
  private var historySizeLimit: Int { max(1, Defaults[.size]) }

  @ObservationIgnored
  /// Copy-count → `PersistentIdentifier` log for the legacy `History.add`
  /// modification-merge path. Keyed by `PersistentIdentifier` (not the
  /// `@Model` ref) so it never retains a `HistoryItem` or its content blobs;
  /// resolved back to the model via `all` in `isModified`. Dead-in-prod (live
  /// ingest is the actor consume path, which bypasses `sessionLog`); retained
  /// so the legacy `History.add` path keeps working if re-enabled.
  private var sessionLog: [Int: PersistentIdentifier] = [:]

  /// All history decorators, including those hidden by the current search.
  /// `items` holds only the visible (filtered) subset.
  @ObservationIgnored
  var all: [HistoryItemDecorator] = []

  @ObservationIgnored
  private let persistence: HistoryPersistence
  @ObservationIgnored
  private let shouldInsertItemsInAdd: Bool
  @ObservationIgnored
  private let logsPersistenceErrors: Bool

  /// Creates the history model with its persistence backend and config flags,
  /// and starts listeners that react to relevant Defaults changes.
  init(
    persistence: HistoryPersistence = SwiftDataHistoryPersistence(),
    shouldInsertItemsInAdd: Bool = History.shouldInsertItemsInAddByDefault(),
    logsPersistenceErrors: Bool = true
  ) {
    self.persistence = persistence
    self.shouldInsertItemsInAdd = shouldInsertItemsInAdd
    self.logsPersistenceErrors = logsPersistenceErrors

    Task { @MainActor in
      for await _ in Defaults.updates(.pasteByDefault, initial: false) {
        updateShortcuts()
      }
    }

    Task { @MainActor in
      for await _ in Defaults.updates(.sortBy, initial: false) {
        await self.loadAfterDefaultsChange()
      }
    }

    Task { @MainActor in
      for await _ in Defaults.updates(.pinTo, initial: false) {
        await self.loadAfterDefaultsChange()
      }
    }

    Task { @MainActor in
      for await _ in Defaults.updates(.showSpecialSymbols, initial: false) {
        for item in items {
          updateTitle(item: item, title: item.item.generateTitle())
        }
      }
    }

    Task { @MainActor in
      for await _ in Defaults.updates(.imageMaxHeight, initial: false) {
        for item in items {
          item.cleanupImages()
        }
      }
    }

    Task { @MainActor in
      for await _ in Defaults.updates(.imageMaxPreviewPixels, initial: false) {
        for item in items {
          item.cleanupImages()
        }
      }
    }
  }

  /// Fetches all items, sorts them, decorates each, and applies the size limit.
  /// Decorator construction is wrapped in `autoreleasepool` to bound the
  /// AppKit transients (e.g. `ApplicationImageCache` misses) to this call.
  func load() async throws {
    let descriptor = FetchDescriptor<HistoryItem>()
    let results = try Storage.shared.context.fetch(descriptor)
    all = autoreleasepool { sorter.sort(results).map { HistoryItemDecorator($0) } }
    items = all

    limitHistorySize(to: historySizeLimit)

    updateShortcuts()
    // Ensure that panel size is proper *after* loading all items.
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  /// Trims unpinned decorators past `maxSize`, deleting the overflow.
  private func limitHistorySize(to maxSize: Int) {
    let maxSize = max(0, maxSize)
    let unpinned = all.filter(\.isUnpinned)
    if unpinned.count > maxSize {
      unpinned[maxSize...].forEach(delete)
    }
  }

  /// Persists a new item via the persistence backend.
  func insertIntoStorage(_ item: HistoryItem) throws {
    logger.info("Inserting history item")
    try persistence.insert(item)
  }

  /// Adds an item through the legacy main-thread path: optionally persists it,
  /// merges any duplicate, enforces the size limit, records it in `sessionLog`,
  /// inserts its decorator at the sorted position, and refreshes visible items.
  /// The live ingest path is the off-main actor's `consume`; this is retained
  /// for the unwired legacy code path.
  @discardableResult
  func add(_ item: HistoryItem) -> HistoryItemDecorator {
    if shouldInsertItemsInAdd {
      do {
        try insertIntoStorage(item)
      } catch {
        recordPersistenceError("Failed to insert history item", error)
        return HistoryItemDecorator(item)
      }
    }

    let removedItemIndex = mergeDuplicateIfNeeded(for: item)
    if removedItemIndex == nil {
      Task {
        Notifier.notify(body: item.title, sound: .write)
      }
    }

    // Remove exceeding items. Do this after the item is added to avoid removing something
    // if a duplicate was found as then the size already stayed the same.
    limitHistorySize(to: historySizeLimit - 1)

    sessionLog[Clipboard.shared.changeCount] = item.persistentModelID

    let itemDecorator = insertDecorator(for: item, removedItemIndex: removedItemIndex)

    refreshVisibleItems()
    AppState.shared.popup.needsResize = true

    return itemDecorator
  }

  /// Applies a `StoreEvent` emitted by the off-main ingest actor, updating the
  /// in-memory `all`/`items` to match the (now-merged) main context.
  ///
  /// `.added`/`.merged` reconcile incrementally — fetch the one committed
  /// `@Model` on main via `ModelContext.model(for: persistentID)` and
  /// binary-insert it at the sorted position (O(log n)), reusing existing
  /// decorators — instead of refetching + re-sorting the whole table every
  /// copy. `.removed`/`.cleared` (not emitted by the ingest actor today), and
  /// any `nil`-persistentID snapshot or `model(for:)` miss, fall back to the
  /// full `reconcileWithStore`. The final `all` order matches the old full sort.
  func consume(_ event: StoreEvent) {
    switch event {
    case .added(let snapshot), .merged(let snapshot):
      insertIncrementally(snapshot)
    case .removed, .cleared:
      // The ingest actor only emits .added/.merged today; handle the others
      // defensively by full reconcile, so a future emitter stays correct.
      reconcileWithStore()
    }
  }

  /// Incremental path for `.added`/`.merged`: fetch the one committed @Model on
  /// main, remove any existing decorator for it (`.merged` re-insert + duplicate
  /// safety), binary-insert it at the sorted position, then sync `all` to the
  /// store (the ingestor may have trimmed an oldest item — `syncAllToStore`).
  /// Falls back to `reconcileWithStore` on any guard failure so correctness never
  /// depends on the fast path.
  private func insertIncrementally(_ snapshot: ItemSnapshotDTO) {
    guard let persistentID = snapshot.persistentID else {
      reconcileWithStore()
      return
    }
    if let existing = all.firstIndex(where: { $0.item.persistentModelID == persistentID }) {
      cleanup(all[existing])
      all.remove(at: existing)
    }
    // `model(for:)` returns the faulted model for a committed id; the title check
    // guards against an un-faulted shell (it returns an unsaved shell for ids it
    // doesn't know). Fall back to the full reconcile if either fails.
    guard let model = Storage.shared.context.model(for: persistentID) as? HistoryItem,
          model.title == snapshot.title else {
      reconcileWithStore()
      return
    }
    let decorator = HistoryItemDecorator(model)
    let position = BinaryInsertion.index(
      for: decorator,
      in: all,
      by: { sorter.areInIncreasingOrder($0.item, $1.item) }
    )
    all.insert(decorator, at: position)
    syncAllToStore()
    refreshVisibleItems()
    if searchQuery.isEmpty && !AppState.shared.navigator.isMultiSelectInProgress {
      AppState.shared.navigator.select(item: unpinnedItems.first ?? pinnedItems.first)
    }
    AppState.shared.popup.needsResize = true
  }

  /// Drops `all` decorators whose backing @Model the ingestor trimmed. The
  /// ingestor deletes oldest-unpinned-by-`lastCopiedAt` beyond `Defaults[.size]`,
  /// which is NOT the UI sort order, so `all` can't trim itself correctly. Uses
  /// `fetchIdentifiers` (ids only — no @Model faulting) so the per-copy sync stays
  /// cheap; this is the only O(n) piece of the incremental path.
  private func syncAllToStore() {
    let storeIDs = Set(
      (try? Storage.shared.context.fetchIdentifiers(FetchDescriptor<HistoryItem>())) ?? []
    )
    var index = all.startIndex
    while index < all.count {
      if storeIDs.contains(all[index].item.persistentModelID) {
        index += 1
      } else {
        cleanup(all[index])
        all.remove(at: index)
      }
    }
  }

  /// Rebuilds `all` from a fresh main-context fetch, reusing decorators whose
  /// `persistentModelID` is still present (so decoded images survive) and
  /// decorating only items that are new or changed.
  private func reconcileWithStore() {
    let sorted: [HistoryItem]
    do {
      sorted = sorter.sort(try Storage.shared.context.fetch(FetchDescriptor<HistoryItem>()))
    } catch {
      recordPersistenceError("Failed to fetch history items for consume", error)
      return
    }

    let existingByID = Dictionary(
      all.map { ($0.item.persistentModelID, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var rebuilt: [HistoryItemDecorator] = []
    for item in sorted {
      if let decorator = existingByID[item.persistentModelID] {
        rebuilt.append(decorator)
      } else {
        rebuilt.append(HistoryItemDecorator(item))
      }
    }
    // Invalidate decorators whose backing items were removed/merged away (parity
    // with `mergeDuplicateIfNeeded`'s `cleanup`) so their decoded images release.
    let rebuiltIDs = Set(rebuilt.map { $0.item.persistentModelID })
    for decorator in all where !rebuiltIDs.contains(decorator.item.persistentModelID) {
      cleanup(decorator)
    }
    all = rebuilt
    refreshVisibleItems()
    if searchQuery.isEmpty && !AppState.shared.navigator.isMultiSelectInProgress {
      AppState.shared.navigator.select(item: unpinnedItems.first ?? pinnedItems.first)
    }
    AppState.shared.popup.needsResize = true
  }

  /// If `item` duplicates an existing one, merges metadata onto `item`, removes
  /// the existing decorator, and returns the index it occupied (else `nil`).
  private func mergeDuplicateIfNeeded(for item: HistoryItem) -> Int? {
    guard let existingHistoryItem = findSimilarItem(item) else {
      return nil
    }

    if isModified(item) == nil {
      item.contents = existingHistoryItem.contents.map {
        HistoryItemContent(type: $0.type, value: $0.value)
      }
    }
    item.firstCopiedAt = existingHistoryItem.firstCopiedAt
    item.numberOfCopies += existingHistoryItem.numberOfCopies
    item.pin = existingHistoryItem.pin
    item.title = existingHistoryItem.title
    if !item.fromMaccy {
      item.application = existingHistoryItem.application
    }

    logger.info("Removing duplicate history item")
    let removedItemIndex = all.firstIndex(where: { $0.item == existingHistoryItem })
    if let removedItemIndex {
      cleanup(all[removedItemIndex])
      all.remove(at: removedItemIndex)
    }
    Storage.shared.context.delete(existingHistoryItem)
    return removedItemIndex
  }

  /// Builds the decorator for `item` and inserts it at the sorted position
  /// (reusing `removedItemIndex` when merging a duplicate pin).
  private func insertDecorator(
    for item: HistoryItem,
    removedItemIndex: Int?
  ) -> HistoryItemDecorator {
    if let pin = item.pin {
      let itemDecorator = HistoryItemDecorator(item, shortcuts: KeyShortcut.create(character: pin))
      if let removedItemIndex {
        all.insert(itemDecorator, at: removedItemIndex)
      }
      return itemDecorator
    }

    let itemDecorator = HistoryItemDecorator(item)
    let sortedItems = sorter.sort(all.map(\.item) + [item])
    if let index = sortedItems.firstIndex(of: item) {
      all.insert(itemDecorator, at: index)
    }
    return itemDecorator
  }

  /// Runs `block` under DEBUG-only before/after row-count logging. The count
  /// round-trips are diagnostics only, so release builds skip them and run just
  /// the operation.
  private func withLogging(_ msg: String, _ block: () throws -> Void) rethrows {
    #if DEBUG
    func dataCounts() -> String {
      do {
        let historyItemCount = try persistence.countHistoryItems()
        let historyContentCount = try persistence.countHistoryItemContents()
        return "HistoryItem=\(historyItemCount) HistoryItemContent=\(historyContentCount)"
      } catch {
        recordPersistenceError("Failed to count history items", error)
        return "HistoryItem=0 HistoryItemContent=0"
      }
    }

    logger.info("\(msg) Before: \(dataCounts())")
    try block()
    logger.info("\(msg) After: \(dataCounts())")
    #else
    try block()
    #endif
  }

  /// Deletes all unpinned items (keeping pins), draining each removed
  /// decorator's AppKit transients in an autorelease pool so a bulk clear
  /// doesn't pile them up.
  func clear() {
    throttler.cancel()
    invalidateInFlightSearch()

    do {
      try withLogging("Clearing history") {
        try persistence.deleteUnpinned()
      }
      for item in all where item.isUnpinned {
        autoreleasepool {
          cleanup(item)
        }
      }
      all.removeAll(where: \.isUnpinned)
      // `all` now holds only pinned survivors (unpinned removed above); drop any
      // sessionLog entry whose backing item is no longer present.
      sessionLog.removeValues { pid in
        !all.contains(where: { $0.item.persistentModelID == pid })
      }
      items = all
    } catch {
      recordPersistenceError("Failed to clear history", error)
      return
    }

    Clipboard.shared.clear()
    AppState.shared.popup.close()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  /// Deletes every item (pins included), draining each decorator's transients.
  func clearAll() {
    throttler.cancel()
    invalidateInFlightSearch()

    do {
      try withLogging("Clearing all history") {
        try persistence.deleteAll()
      }
      for item in all {
        autoreleasepool {
          cleanup(item)
        }
      }
      all.removeAll()
      sessionLog.removeAll()
      items = all
    } catch {
      recordPersistenceError("Failed to clear all history", error)
      return
    }

    Clipboard.shared.clear()
    AppState.shared.popup.close()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  /// Deletes a single decorator's backing item, removes it from `all`/`items`,
  /// drops its `sessionLog` entry, and reassigns unpinned shortcuts.
  func delete(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    throttler.cancel()
    invalidateInFlightSearch()
    do {
      try withLogging("Removing history item") {
        try persistence.delete(item.item)
      }
    } catch {
      recordPersistenceError("Failed to delete history item", error)
      return
    }

    cleanup(item)
    all.removeAll { $0 == item }
    items.removeAll { $0 == item }
    sessionLog.removeValues { $0 == item.item.persistentModelID }

    updateUnpinnedShortcuts()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  /// Invalidates a decorator, releasing its transient images.
  private func cleanup(_ item: HistoryItemDecorator) {
    item.invalidate()
  }

  /// The current event's relevant modifier flags (device-independent, caps/num/fn stripped).
  private func currentModifierFlags() -> NSEvent.ModifierFlags {
    return NSApp.currentEvent?.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function]) ?? []
  }

  /// Copies (and optionally pastes) the item, choosing the copy/paste variant
  /// from the held modifier flags, then clears the search query.
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

  /// Begins a multi-select paste stack: copies the first selected item and
  /// stores the remaining items for sequential pasting.
  func startPasteStack(selection: inout Selection<HistoryItemDecorator>) {
    guard AppState.shared.multiSelectionEnabled else { return }
    guard let item = selection.first else { return }
    PasteStack.initializeIfNeeded()

    let modifierFlags = currentModifierFlags()

    let stack = PasteStack(items: selection.items, modifierFlags: modifierFlags)
    pasteStack = stack

    logger.info("Initialising PasteStack with \(stack.items.count) items")
    logger.info("Copying item from PasteStack")

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

  /// Pastes the next item in an active paste stack, or clears it when empty.
  func handlePasteStack() {
    guard let stack = pasteStack else {
      return
    }

    guard !stack.items.isEmpty else {
      pasteStack = nil
      logger.info("PasteStack is empty")
      return
    }

    logger.info("PasteStack pasted item")

    stack.items.removeFirst()

    guard let item = stack.items.first else {
      pasteStack = nil
      logger.info("PasteStack is empty")
      return
    }

    logger.info("Copying item from PasteStack. \(stack.items.count) items remaining in stack.")

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

  /// Cancels an in-progress paste stack.
  func interruptPasteStack() {
    guard pasteStack != nil else {
      return
    }
    logger.info("Interrupting PasteStack")
    pasteStack = nil
  }

  /// Toggles an item's pin, persists it, re-sorts `all`, and clears the query.
  func togglePin(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    let previousPin = item.item.pin
    item.togglePin()
    do {
      try persistence.save()
    } catch {
      item.item.pin = previousPin
      recordPersistenceError("Failed to save pinned history item", error)
      return
    }

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

  /// Returns an existing item that supersedes `item` (or a session-logged
  /// modification of it), else `nil`. Used by the legacy `add` path.
  private func findSimilarItem(_ item: HistoryItem) -> HistoryItem? {
    do {
      let all = try persistence.fetchAll()
      let signature = item.duplicateSignature
      for existingItem in all where existingItem != item {
        if existingItem.supersedes(signature) {
          return existingItem
        }
      }

      return isModified(item)
    } catch {
      recordPersistenceError("Failed to fetch history items", error)
      return nil
    }
  }

  /// Reloads the history after a Defaults change that affects ordering/display.
  private func loadAfterDefaultsChange() async {
    do {
      try await load()
    } catch {
      recordPersistenceError("Failed to reload history", error)
    }
  }

  /// Stores `error` on `lastPersistError` and logs it when enabled.
  private func recordPersistenceError(_ message: String, _ error: Error) {
    lastPersistError = error
    if logsPersistenceErrors {
      logger.error("\(message): \(String(describing: error))")
    }
  }

  /// Whether `add` should persist by default (true on macOS 15+, where SwiftData
  /// main-context auto-save is reliable; false on older OSes).
  nonisolated private static func shouldInsertItemsInAddByDefault() -> Bool {
    if #available(macOS 15.0, *) {
      return true
    } else {
      return false
    }
  }

  /// Returns the logged duplicate of `item` if it was modified this session, else `nil`.
  private func isModified(_ item: HistoryItem) -> HistoryItem? {
    if let modified = item.modified, let pid = sessionLog[modified] {
      return all.first { $0.item.persistentModelID == pid }?.item
    }

    return nil
  }

  /// Rebuilds `items` from search results, applying highlights and refreshing shortcuts.
  private func updateItems(_ newItems: [Search.SearchResult]) {
    items = newItems.map { result in
      let item = result.object
      item.highlight(searchQuery, result.ranges)

      return item
    }

    updateUnpinnedShortcuts()
  }

  /// Refreshes `items`: `all` when the query is empty, else the filtered matches.
  private func refreshVisibleItems() {
    if searchQuery.isEmpty {
      items = all
      updateUnpinnedShortcuts()
    } else {
      updateItems(search.search(string: searchQuery, within: all))
    }
  }

  // MARK: - Off-main search

  /// Throttled search entry point. Two paths:
  ///  - empty query: short-circuit SYNCHRONOUSLY on main (reuses the unchanged
  ///    legacy `search.search("", within: all)` → all items, highlights cleared).
  ///    No actor hop, so clearing the query never flickers.
  ///  - non-empty: bump generation, cancel any in-flight task, snapshot the
  ///    corpus as Sendable DTOs (id+title — never the @Model), and run the
  ///    4-mode match off-main on `searchActor`. The Task inherits @MainActor
  ///    from this method, so after the actor hop it resumes on main and applies
  ///    generation-guarded.
  private func performSearch() {
    if searchQuery.isEmpty {
      invalidateInFlightSearch()
      // Byte-identical to the legacy didSet empty path: search.search("") returns
      // all items with empty ranges; updateItems clears each highlight.
      updateItems(search.search(string: "", within: all))
      AppState.shared.navigator.select(item: unpinnedItems.first)
      AppState.shared.popup.needsResize = true
      return
    }

    searchGeneration &+= 1
    let myGeneration = searchGeneration
    searchTask?.cancel()

    let query = searchQuery
    let mode = Defaults[.searchMode]
    let corpus = all.map { SearchCorpusItem(id: $0.id, title: $0.title) }
    let actor = searchActor

    searchTask = Task { [weak self] in
      let matches = await actor.search(query: query, within: corpus, mode: mode)
      // Task inherits @MainActor; after the actor hop we resume on main.
      guard !Task.isCancelled, let self else { return }
      self.applySearchResults(matches, for: query, generation: myGeneration)
    }
  }

  /// Applies an off-main search result on main. Discarded if a newer keystroke,
  /// an ingest, or a destructive op bumped `searchGeneration` past `generation`.
  /// Resolves DTO ids back to decorators (skipping ids no longer in `all`, e.g.
  /// deleted mid-search), highlights only where the title still equals the
  /// snapshot (equality guard — else `Int` offsets could be out of bounds),
  /// rebuilds `items`, and runs the same side effects as the legacy didSet.
  private func applySearchResults(_ matches: [SearchMatchDTO], for query: String, generation: Int) {
    guard searchGeneration == generation else { return }

    var rebuilt: [HistoryItemDecorator] = []
    for dto in matches {
      guard let decorator = all.first(where: { $0.id == dto.id }) else { continue }
      if decorator.title == dto.title {
        let ranges = dto.ranges.map { indexRange($0, in: decorator.title) }
        decorator.highlight(query, ranges)
      } else {
        // Title changed since the corpus snapshot — offsets may be stale, so
        // skip highlighting (clear it) but still keep the match in `items`.
        decorator.highlight("", [])
      }
      rebuilt.append(decorator)
    }
    items = rebuilt
    updateUnpinnedShortcuts()

    if query.isEmpty {
      AppState.shared.navigator.select(item: unpinnedItems.first)
    } else {
      AppState.shared.navigator.highlightFirst()
    }
    AppState.shared.popup.needsResize = true
  }

  /// Converts a DTO range (Character/grapheme offsets, exclusive upper bound)
  /// back to `Range<String.Index>` via `index(offsetBy:)` — grapheme-correct,
  /// the exact inverse of how the actor produced the offsets. Only called under
  /// the equality guard (title == dto.title), so offsets are in-bounds; the
  /// clamp is defensive crash insurance only.
  private func indexRange(_ dtoRange: Range<Int>, in title: String) -> Range<String.Index> {
    let count = title.count
    let lower = max(0, min(dtoRange.lowerBound, count))
    let upper = max(lower, min(dtoRange.upperBound, count))
    let start = title.startIndex
    return title.index(start, offsetBy: lower)..<title.index(start, offsetBy: upper)
  }

  /// Bumps `searchGeneration` and cancels + nils the in-flight search Task.
  /// Called by every synchronous `items` mutation path (clear/clearAll/delete,
  /// empty short-circuit, new-search kickoff) so a stale off-main apply is
  /// discarded by the generation guard in `applySearchResults`.
  private func invalidateInFlightSearch() {
    searchGeneration &+= 1
    searchTask?.cancel()
    searchTask = nil
  }

  /// Rebuilds pin shortcuts and then unpinned ones.
  private func updateShortcuts() {
    for item in pinnedItems {
      if let pin = item.item.pin {
        item.shortcuts = KeyShortcut.create(character: pin)
      }
    }

    updateUnpinnedShortcuts()
  }

  /// Sets both the decorator's and model's title.
  private func updateTitle(item: HistoryItemDecorator, title: String) {
    item.title = title
    item.item.title = title
  }

  /// Assigns `1`–`9` shortcuts to the first nine visible unpinned items.
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

extension History: HistoryRef {
  /// All decorators (visible or not), for memory-pressure iteration.
  func decorators() -> [HistoryItemDecorator] { all }
}
