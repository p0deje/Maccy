// swiftlint:disable file_length
import AppKit.NSRunningApplication
import Defaults
import Foundation
import Logging
import Observation
import Sauce
import Settings
import SwiftData

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
  func fetchAll() throws -> [HistoryItem]
  @MainActor
  func countHistoryItems() throws -> Int
  @MainActor
  func countHistoryItemContents() throws -> Int
}

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

@Observable
class History: ItemsContainer { // swiftlint:disable:this type_body_length
  static let shared = History()
  let logger = Logger(label: "org.p0deje.Maccy")

  var items: [HistoryItemDecorator] = []
  var pasteStack: PasteStack?
  var lastPersistError: Error?

  var pinnedItems: [HistoryItemDecorator] { items.filter(\.isPinned) }
  var unpinnedItems: [HistoryItemDecorator] { items.filter(\.isUnpinned) }

  var searchQuery: String = "" {
    didSet {
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
  private var historySizeLimit: Int { max(1, Defaults[.size]) }

  @ObservationIgnored
  private var sessionLog: [Int: HistoryItem] = [:]

  // The distinction between `all` and `items` is the following:
  // - `all` stores all history items, even the ones that are currently hidden by a search
  // - `items` stores only visible history items, updated during a search
  @ObservationIgnored
  var all: [HistoryItemDecorator] = []

  @ObservationIgnored
  private let persistence: HistoryPersistence
  @ObservationIgnored
  private let shouldInsertItemsInAdd: Bool
  @ObservationIgnored
  private let logsPersistenceErrors: Bool

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
  }

  @MainActor
  func load() async throws {
    let descriptor = FetchDescriptor<HistoryItem>()
    let results = try Storage.shared.context.fetch(descriptor)
    all = sorter.sort(results).map { HistoryItemDecorator($0) }
    items = all

    limitHistorySize(to: historySizeLimit)

    updateShortcuts()
    // Ensure that panel size is proper *after* loading all items.
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  private func limitHistorySize(to maxSize: Int) {
    let maxSize = max(0, maxSize)
    let unpinned = all.filter(\.isUnpinned)
    if unpinned.count > maxSize {
      unpinned[maxSize...].forEach(delete)
    }
  }

  @MainActor
  func insertIntoStorage(_ item: HistoryItem) throws {
    logger.info("Inserting history item")
    try persistence.insert(item)
  }

  @discardableResult
  @MainActor
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

    sessionLog[Clipboard.shared.changeCount] = item

    let itemDecorator = insertDecorator(for: item, removedItemIndex: removedItemIndex)

    refreshVisibleItems()
    AppState.shared.popup.needsResize = true

    return itemDecorator
  }

  /// Applies a `StoreEvent` emitted by the background ingest actor, updating the
  /// in-memory `all`/`items` to match the (now-merged) main context.
  ///
  /// The actor commits on a background `ModelContext` whose saves merge into the
  /// main context (`Storage.newBackgroundContext()` sets
  /// `automaticallyMergesChangesFromParent`). Because a `StoreEvent` carries only
  /// the lightweight `ItemSnapshotDTO` (no fetchable SwiftData id), `.added`/
  /// `.merged` reconcile against a fresh main-context fetch: existing decorators
  /// are reused by `persistentModelID` so unchanged items keep their decoded
  /// images, only new/changed items get freshly decorated. The O(n) fetch here
  /// matches the current `History.add` cost; BS-4 makes insertion O(log n).
  @MainActor
  func consume(_ event: StoreEvent) {
    switch event {
    case .added, .merged:
      reconcileWithStore()
    case .removed, .cleared:
      // The BS-2 actor only emits .added/.merged today; handle the others
      // defensively by reconciling too, so a future emitter stays correct.
      reconcileWithStore()
    }
  }

  /// Rebuilds `all` from a fresh main-context fetch, reusing decorators whose
  /// `persistentModelID` is still present (so decoded images survive) and
  /// decorating only items that are new or changed.
  @MainActor
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
    AppState.shared.popup.needsResize = true
  }

  @MainActor
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

  @MainActor
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

  @MainActor
  private func withLogging(_ msg: String, _ block: () throws -> Void) rethrows {
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
  }

  @MainActor
  func clear() {
    throttler.cancel()

    do {
      try withLogging("Clearing history") {
        try persistence.deleteUnpinned()
      }
      all.forEach { item in
        if item.isUnpinned {
          cleanup(item)
        }
      }
      all.removeAll(where: \.isUnpinned)
      sessionLog.removeValues { $0.pin == nil }
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

  @MainActor
  func clearAll() {
    throttler.cancel()

    do {
      try withLogging("Clearing all history") {
        try persistence.deleteAll()
      }
      all.forEach { item in
        cleanup(item)
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

  @MainActor
  func delete(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    throttler.cancel()
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
    sessionLog.removeValues { $0 == item.item }

    updateUnpinnedShortcuts()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  private func cleanup(_ item: HistoryItemDecorator) {
    item.invalidate()
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

  @MainActor
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

  @MainActor
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

  @MainActor
  private func loadAfterDefaultsChange() async {
    do {
      try await load()
    } catch {
      recordPersistenceError("Failed to reload history", error)
    }
  }

  @MainActor
  private func recordPersistenceError(_ message: String, _ error: Error) {
    lastPersistError = error
    if logsPersistenceErrors {
      logger.error("\(message): \(String(describing: error))")
    }
  }

  private static func shouldInsertItemsInAddByDefault() -> Bool {
    if #available(macOS 15.0, *) {
      return true
    } else {
      return false
    }
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

  private func refreshVisibleItems() {
    if searchQuery.isEmpty {
      items = all
      updateUnpinnedShortcuts()
    } else {
      updateItems(search.search(string: searchQuery, within: all))
    }
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
