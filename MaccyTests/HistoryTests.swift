import AppKit
import Testing
import Defaults
import SwiftData
@testable import Maccy

extension SharedStateTests {
  @MainActor
  final class HistoryTests { // swiftlint:disable:this type_body_length
    let savedSize = Defaults[.size]
    let savedSortBy = Defaults[.sortBy]
    let savedPinOrder = Defaults[.pinOrder]
    let savedPinTo = Defaults[.pinTo]
    let history = History.shared

    init() {
      History.shared.clearAll()
      Defaults[.size] = 10
      Defaults[.sortBy] = .firstCopiedAt
      Defaults[.pinOrder] = PinOrder()
      Defaults[.pinTo] = .bottom
    }

    deinit {
      Defaults[.size] = savedSize
      Defaults[.sortBy] = savedSortBy
      Defaults[.pinOrder] = savedPinOrder
      Defaults[.pinTo] = savedPinTo
    }

    @Test("Default is empty")
    func defaultIsEmpty() {
      #expect(history.items.toArray() == [])
    }

    @Test("Storage directories preserve legacy history")
    func storageDirectoriesPreserveLegacyHistory() {
      #expect(Storage.storageDirectoryName(for: "org.p0deje.Maccy") == "Maccy")
      #expect(Storage.storageDirectoryName(for: "org.p0deje.Maccy.dev") == "MaccyDev")
      #expect(Storage.storageDirectoryName(for: "org.laiyongqiang.MaccyProtected") == "Maccy")
      #expect(Storage.storageDirectoryName(for: nil) == "Maccy")
    }

    @Test("Adding")
    func adding() {
      let first = history.add(historyItem("foo"))
      let second = history.add(historyItem("bar"))
      #expect(history.items.toArray() == [second, first])
    }

    @Test("Adding persisted duplicate")
    func addingPersistedDuplicate() throws {
      let first = historyItem("foo")
      first.title = "xyz"
      first.application = "iTerm.app"
      history.add(first)
      first.pin = "f"

      let third = historyItem("foo")
      third.application = "Xcode.app"
      let transferredContents = first.contents
      let merged = history.add(third)

      #expect(history.items.toArray() == [merged])
      #expect(Set(merged.item.contents) == Set(transferredContents))
      #expect(merged.item.lastCopiedAt > merged.item.firstCopiedAt)
      #expect(merged.item.numberOfCopies == 2)
      #expect(merged.item.pin == "f")
      #expect(merged.item.title == "xyz")
      #expect(merged.item.application == "iTerm.app")
      try assertStorageCounts(items: 1, contents: 1)
    }

    @Test("Duplicate copy inherits protected state")
    func duplicateCopyInheritsProtectedState() throws {
      let first = history.add(historyItem("protected duplicate"))
      history.toggleProtection(first)

      let duplicate = history.add(historyItem("protected duplicate"))

      #expect(duplicate.isProtected)
      #expect(history.items.toArray() == [duplicate])
      try assertStorageCounts(items: 1, contents: 1)
    }

    @Test("Protection does not change history order")
    func protectionDoesNotChangeHistoryOrder() {
      let older = history.add(historyItem("older"))
      let newer = history.add(historyItem("newer"))
      #expect(history.items.toArray() == [newer, older])

      history.toggleProtection(older)

      #expect(history.items.toArray() == [newer, older])
    }

    @Test("Protection change invalidates decorator observers")
    func protectionChangeInvalidatesDecoratorObservers() {
      final class ObservedChange: @unchecked Sendable {
        private let lock = NSLock()
        private var detected = false

        var didChange: Bool {
          lock.withLock { detected }
        }

        func markChanged() {
          lock.withLock { detected = true }
        }
      }

      let change = ObservedChange()
      let item = history.add(historyItem("observed protection"))

      withObservationTracking {
        _ = item.isProtected
      } onChange: {
        change.markChanged()
      }

      history.toggleProtection(item)
      #expect(change.didChange)
    }

    @Test("Protection rolls back when persistence fails")
    func protectionRollsBackWhenPersistenceFails() {
      struct SimulatedSaveError: Error {}

      let item = history.add(historyItem("rollback me"))
      let succeeded = history.toggleProtection(item) {
        throw SimulatedSaveError()
      }

      #expect(!succeeded)
      #expect(!item.isProtected)
    }

    @Test("Failed storage actions publish an error and successful actions clear it")
    func failedStorageActionsPublishAnError() {
      struct SimulatedSaveError: Error {}

      let appState = AppState.shared
      let previousError = appState.storageErrorMessage
      defer { appState.storageErrorMessage = previousError }
      let item = history.add(historyItem("failed protection"))

      #expect(!appState.runStorageAction {
        history.toggleProtection(item) { throw SimulatedSaveError() }
      })
      #expect(appState.storageErrorMessage != nil)
      #expect(appState.suppressPopupAutoClose)
      #expect(!item.isProtected)

      #expect(appState.runStorageAction { history.toggleProtection(item) })
      #expect(appState.storageErrorMessage == nil)
      #expect(item.isProtected)
    }

    @Test("Protection failure preserves unrelated pending changes")
    func protectionFailurePreservesUnrelatedPendingChanges() {
      struct SimulatedSaveError: Error {}

      let item = history.add(historyItem("preserve pending state"))
      history.togglePin(item)

      let succeeded = history.toggleProtection(item) {
        throw SimulatedSaveError()
      }

      #expect(!succeeded)
      #expect(!item.isProtected)
      #expect(item.isPinned)
      #expect(history.pinnedItems == [item])
    }

    @Test("Adding unsaved duplicate")
    @available(macOS 15.0, *)
    func addingUnsavedDuplicate() throws {
      let first = historyItem("foo")
      first.title = "xyz"
      first.application = "iTerm.app"
      history.add(first)
      first.pin = "f"

      let second = historyItem("foo", persisted: false)
      second.application = "Xcode.app"
      let transferredContents = first.contents
      let merged = history.add(second)

      #expect(history.items.toArray() == [merged])
      #expect(Set(merged.item.contents) == Set(transferredContents))
      #expect(merged.item.lastCopiedAt > merged.item.firstCopiedAt)
      #expect(merged.item.numberOfCopies == 2)
      #expect(merged.item.pin == "f")
      #expect(merged.item.title == "xyz")
      #expect(merged.item.application == "iTerm.app")
      try assertStorageCounts(items: 1, contents: 1)
    }

    @Test("Adding item that is superseded by existing")
    func addingItemThatIsSupersededByExisting() throws {
      let firstContents = [
        HistoryItemContent(
          type: NSPasteboard.PasteboardType.string.rawValue,
          value: "one".data(using: .utf8)!
        ),
        HistoryItemContent(
          type: NSPasteboard.PasteboardType.rtf.rawValue,
          value: "two".data(using: .utf8)!
        )
      ]
      let firstItem = HistoryItem()
      Storage.shared.context.insert(firstItem)
      firstItem.application = "Maccy.app"
      firstItem.contents = firstContents
      firstItem.title = firstItem.generateTitle()
      history.add(firstItem)

      let secondContents = [
        HistoryItemContent(
          type: NSPasteboard.PasteboardType.string.rawValue,
          value: "one".data(using: .utf8)!
        )
      ]
      let secondItem = HistoryItem()
      Storage.shared.context.insert(secondItem)
      secondItem.application = "Maccy.app"
      secondItem.contents = secondContents
      secondItem.title = secondItem.generateTitle()
      let second = history.add(secondItem)

      #expect(history.items.toArray() == [second])
      #expect(Set(history.items[0].item.contents) == Set(firstContents))
      try assertStorageCounts(items: 1, contents: firstContents.count)
    }

    @Test("Adding item with different modified type")
    func addingItemWithDifferentModifiedType() {
      let firstContents = [
        HistoryItemContent(
          type: NSPasteboard.PasteboardType.string.rawValue,
          value: "one".data(using: .utf8)!
        ),
        HistoryItemContent(
          type: NSPasteboard.PasteboardType.modified.rawValue,
          value: "1".data(using: .utf8)!
        )
      ]
      let firstItem = HistoryItem()
      Storage.shared.context.insert(firstItem)
      firstItem.contents = firstContents
      history.add(firstItem)

      let secondContents = [
        HistoryItemContent(
          type: NSPasteboard.PasteboardType.string.rawValue,
          value: "one".data(using: .utf8)!
        ),
        HistoryItemContent(
          type: NSPasteboard.PasteboardType.modified.rawValue,
          value: "2".data(using: .utf8)!
        )
      ]
      let secondItem = HistoryItem()
      Storage.shared.context.insert(secondItem)
      secondItem.contents = secondContents
      let second = history.add(secondItem)

      #expect(history.items.toArray() == [second])
      #expect(Set(history.items[0].item.contents) == Set(firstContents))
    }

    @Test("Adding item from Maccy")
    func addingItemFromMaccy() {
      let firstContents = [
        HistoryItemContent(
          type: NSPasteboard.PasteboardType.string.rawValue,
          value: "one".data(using: .utf8)
        )
      ]
      let first = HistoryItem()
      Storage.shared.context.insert(first)
      first.application = "Xcode.app"
      first.contents = firstContents
      history.add(first)

      let secondContents = [
        HistoryItemContent(
          type: NSPasteboard.PasteboardType.string.rawValue,
          value: "one".data(using: .utf8)
        ),
        HistoryItemContent(
          type: NSPasteboard.PasteboardType.fromMaccy.rawValue,
          value: "".data(using: .utf8)
        )
      ]
      let second = HistoryItem()
      Storage.shared.context.insert(second)
      second.application = "Maccy.app"
      second.contents = secondContents
      let secondDecorator = history.add(second)

      #expect(history.items.toArray() == [secondDecorator])
      #expect(history.items[0].item.application == "Xcode.app")
      #expect(Set(history.items[0].item.contents) == Set(firstContents))
    }

    @Test("Modified after copying")
    func modifiedAfterCopying() {
      history.add(historyItem("foo"))

      let modifiedItem = historyItem("bar")
      modifiedItem.contents.append(HistoryItemContent(
        type: NSPasteboard.PasteboardType.modified.rawValue,
        value: String(Clipboard.shared.changeCount).data(using: .utf8)
      ))
      let modifiedItemDecorator = history.add(modifiedItem)

      #expect(history.items.toArray() == [modifiedItemDecorator])
      #expect(history.items[0].text == "bar")
    }

    @Test("Clearing unpinned")
    func clearingUnpinned() throws {
      let pinned = history.add(historyItem("foo"))
      history.togglePin(pinned)
      history.add(historyItem("bar"))
      let orphan = HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "orphan".data(using: .utf8)
      )
      Storage.shared.context.insert(orphan)
      try Storage.shared.context.save()

      history.clear()

      #expect(history.items.toArray() == [pinned])
      try assertStorageCounts(items: 1, contents: 1)
    }

    @Test("Clearing preserves protected and pinned items")
    func clearingPreservesProtectedAndPinnedItems() throws {
      let pinned = history.add(historyItem("pinned"))
      history.togglePin(pinned)
      let protected = history.add(historyItem("protected"))
      history.toggleProtection(protected)
      let pinnedAndProtected = history.add(historyItem("pinned and protected"))
      history.togglePin(pinnedAndProtected)
      history.toggleProtection(pinnedAndProtected)
      history.add(historyItem("ordinary"))

      history.clear()

      #expect(history.items.contains(pinned))
      #expect(history.items.contains(protected))
      #expect(history.items.contains(pinnedAndProtected))
      #expect(history.items.count == 3)
      try assertStorageCounts(items: 3, contents: 3)
    }

    @Test("Clearing renumbers protected item shortcuts")
    func clearingRenumbersProtectedItemShortcuts() {
      let protected = history.add(historyItem("protected"))
      history.toggleProtection(protected)
      history.add(historyItem("ordinary"))
      #expect(protected.shortcuts.first?.key == .two)

      #expect(history.clear())

      #expect(history.unpinnedItems == [protected])
      #expect(protected.shortcuts.first?.key == .one)
    }

    @Test("Clearing assigns shortcuts to protected items beyond the first nine")
    func clearingAssignsShortcutsToProtectedItemsBeyondFirstNine() {
      let protected = history.add(historyItem("protected"))
      history.toggleProtection(protected)
      for index in 0..<10 {
        history.add(historyItem("ordinary \(index)"))
      }
      #expect(protected.shortcuts.isEmpty)

      #expect(history.clear())

      #expect(history.unpinnedItems == [protected])
      #expect(protected.shortcuts.first?.key == .one)
    }

    @Test("Failed clear preserves history and clipboard")
    func failedClearPreservesHistoryAndClipboard() throws {
      struct SimulatedSaveError: Error {}

      let pinned = history.add(historyItem("pinned failure"))
      history.togglePin(pinned)
      let protected = history.add(historyItem("protected failure"))
      history.toggleProtection(protected)
      let ordinary = history.add(historyItem("ordinary failure"))
      let historyBefore = history.items.toArray()

      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString("keep clipboard", forType: .string)
      let markerData = Data("keep custom clipboard".utf8)
      let markerType = NSPasteboard.PasteboardType("MaccyTests.ClipboardMarker")
      pasteboard.setData(markerData, forType: markerType)

      let succeeded = history.clear { context in
        try context.transaction {
          let contents = try context.fetch(FetchDescriptor<HistoryItemContent>(
            predicate: #Predicate {
              $0.item == nil || ($0.item?.pin == nil && $0.item?.isProtected == false)
            }
          ))
          contents.forEach(context.delete)

          let items = try context.fetch(FetchDescriptor<HistoryItem>(
            predicate: #Predicate { $0.pin == nil && !$0.isProtected }
          ))
          items.forEach(context.delete)
          throw SimulatedSaveError()
        }
      }

      #expect(!succeeded)
      #expect(history.items.toArray() == historyBefore)
      #expect(history.items.contains(ordinary))
      #expect(ordinary.item.title == "ordinary failure")
      #expect(history.pinnedItems == [pinned])
      #expect(pasteboard.string(forType: .string) == "keep clipboard")
      #expect(pasteboard.data(forType: markerType) == markerData)
      try assertStorageCounts(items: 3, contents: 3)
      try assertPersistedStorageCounts(items: 3, contents: 3)
    }

    @Test("Failed clear all preserves history and clipboard")
    func failedClearAllPreservesHistoryAndClipboard() throws {
      struct SimulatedSaveError: Error {}

      let pinned = history.add(historyItem("pinned all failure"))
      history.togglePin(pinned)
      let protected = history.add(historyItem("protected all failure"))
      history.toggleProtection(protected)
      let ordinary = history.add(historyItem("ordinary all failure"))
      let historyBefore = history.items.toArray()

      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString("keep clipboard", forType: .string)
      let markerData = Data("keep custom clipboard".utf8)
      let markerType = NSPasteboard.PasteboardType("MaccyTests.ClipboardMarker")
      pasteboard.setData(markerData, forType: markerType)

      let succeeded = history.clearAll { context in
        try context.transaction {
          let contents = try context.fetch(FetchDescriptor<HistoryItemContent>())
          contents.forEach(context.delete)

          let items = try context.fetch(FetchDescriptor<HistoryItem>())
          items.forEach(context.delete)
          throw SimulatedSaveError()
        }
      }

      #expect(!succeeded)
      #expect(history.items.toArray() == historyBefore)
      #expect(history.items.contains(ordinary))
      #expect(ordinary.item.title == "ordinary all failure")
      #expect(history.pinnedItems == [pinned])
      #expect(pasteboard.string(forType: .string) == "keep clipboard")
      #expect(pasteboard.data(forType: markerType) == markerData)
      try assertStorageCounts(items: 3, contents: 3)
      try assertPersistedStorageCounts(items: 3, contents: 3)
    }

    @Test("Clear intent reports a read-only database failure")
    func clearIntentReportsReadOnlyDatabaseFailure() async throws {
      let originalContainer = Storage.shared.container
      let suppressClearAlert = Defaults[.suppressClearAlert]
      let ignoreEvents = Defaults[.ignoreEvents]
      let ignoreOnlyNextEvent = Defaults[.ignoreOnlyNextEvent]
      let (directory, url) = try temporaryDatabaseLocation()
      let writable = try ModelContainer(for: HistoryItem.self, configurations: ModelConfiguration(url: url))
      Storage.shared.container = writable
      defer {
        Storage.shared.container = writable
        history.clearAll()
        Storage.shared.container = originalContainer
        Defaults[.suppressClearAlert] = suppressClearAlert
        Defaults[.ignoreEvents] = ignoreEvents
        Defaults[.ignoreOnlyNextEvent] = ignoreOnlyNextEvent
        try? FileManager.default.removeItem(at: directory)
      }
      history.add(historyItem("read-only history"))
      try Storage.shared.context.save()
      Storage.shared.container = try ModelContainer(
        for: HistoryItem.self,
        configurations: ModelConfiguration(url: url, allowsSave: false)
      )
      Defaults[.suppressClearAlert] = true
      // Awaiting the intent lets the clipboard timer run while the test store
      // is read-only. Do not import unrelated system clipboard contents.
      Defaults[.ignoreEvents] = true
      Defaults[.ignoreOnlyNextEvent] = false

      await #expect(throws: HistoryStorageError.self) {
        _ = try await Clear().perform()
      }

      #expect(history.items.count == 1)
      let persisted = try Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
      #expect(persisted.first?.text == "read-only history")
    }

    @Test("Clearing all")
    func clearingAll() throws {
      history.add(historyItem("foo"))
      let pinned = history.add(historyItem("bar"))
      history.togglePin(pinned)
      let protected = history.add(historyItem("protected"))
      history.toggleProtection(protected)
      Storage.shared.context.insert(HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "orphan".data(using: .utf8)
      ))
      try Storage.shared.context.save()

      history.clearAll()

      #expect(history.items.toArray() == [])
      try assertStorageCounts(items: 0, contents: 0)
    }

    @Test("Max size")
    func maxSize() throws {
      var items: [HistoryItemDecorator] = []
      for index in 0...10 {
        items.append(history.add(historyItem(String(index))))
      }

      #expect(history.items.count == 10)
      #expect(history.items.contains(items[10]))
      #expect(!history.items.contains(items[0]))
      try assertStorageCounts(items: 10, contents: 10)
    }

    @Test("Max size ignores pinned")
    func maxSizeIgnoresPinned() {
      var items: [HistoryItemDecorator] = []

      let item = history.add(historyItem("0"))
      items.append(item)
      history.togglePin(item)

      for index in 1...11 {
        items.append(history.add(historyItem(String(index))))
      }

      #expect(history.items.count == 11)
      #expect(history.items.contains(items[10]))
      #expect(history.items.contains(items[0]))
      #expect(!history.items.contains(items[1]))
    }

    @Test("Max size ignores protected")
    func maxSizeIgnoresProtected() throws {
      Defaults[.size] = 3
      let protected = history.add(historyItem("protected"))
      history.toggleProtection(protected)

      var ordinary: [HistoryItemDecorator] = []
      for index in 0...3 {
        ordinary.append(history.add(historyItem(String(index))))
      }

      #expect(history.items.count == 4)
      #expect(history.items.contains(protected))
      #expect(history.items.contains(ordinary[3]))
      #expect(!history.items.contains(ordinary[0]))
      try assertStorageCounts(items: 4, contents: 4)
    }

    @Test("Protected duplicate at full capacity stays beyond ordinary capacity")
    func protectedDuplicateAtFullCapacity() throws {
      Defaults[.size] = 2
      let protected = history.add(historyItem("protected"))
      history.toggleProtection(protected)

      for index in 0..<Defaults[.size] {
        history.add(historyItem("ordinary \(index)"))
      }

      let duplicate = history.add(historyItem("protected"))

      #expect(duplicate.isProtected)
      #expect(history.items.count == 3)
      #expect(history.unpinnedItems.filter { !$0.isProtected }.count == 2)
      try assertStorageCounts(items: 3, contents: 3)
    }

    @Test("Unprotected items become eligible for capacity cleanup")
    func unprotectedItemsBecomeEligibleForCapacityCleanup() throws {
      Defaults[.size] = 3
      let protectedItem = historyItem("old protected")
      protectedItem.firstCopiedAt = Date(timeIntervalSince1970: 0)
      let protected = history.add(protectedItem)
      history.toggleProtection(protected)

      for index in 0..<3 {
        history.add(historyItem("ordinary \(index)"))
      }
      #expect(history.items.contains(protected))

      history.toggleProtection(protected)
      #expect(!protected.isProtected)
      history.add(historyItem("new ordinary"))

      #expect(!history.items.contains(protected))
      #expect(history.unpinnedItems.count == 3)
      try assertStorageCounts(items: 3, contents: 3)
    }

    @Test("Protected state persists after reopening the database")
    func protectedStatePersistsAfterReopeningDatabase() throws {
      let (directory, url) = try temporaryDatabaseLocation()
      defer { try? FileManager.default.removeItem(at: directory) }
      let title = "persistent protected item"

      do {
        let container = try ModelContainer(for: HistoryItem.self, configurations: ModelConfiguration(url: url))
        let context = container.mainContext
        let item = HistoryItem()
        item.title = title
        item.isProtected = true
        context.insert(item)
        try context.save()
      }

      do {
        let container = try ModelContainer(for: HistoryItem.self, configurations: ModelConfiguration(url: url))
        let context = container.mainContext
        let items = try context.fetch(FetchDescriptor<HistoryItem>())
        let item = try #require(items.first { $0.title == title })
        #expect(item.isProtected)
      }
    }

    @Test("Opening a pre-protection database preserves existing history")
    func openingPreProtectionDatabasePreservesExistingHistory() throws {
      let (directory, url) = try temporaryDatabaseLocation()
      defer { try? FileManager.default.removeItem(at: directory) }
      let title = "legacy clipboard item"
      let application = "com.example.LegacyApp"
      let firstCopiedAt = Date(timeIntervalSince1970: 1_700_000_000)
      let lastCopiedAt = Date(timeIntervalSince1970: 1_700_000_100)
      let numberOfCopies = 7
      let pin = "f"
      let stringValue = Data("legacy text".utf8)
      let rtfValue = Data(repeating: 0xAB, count: 32)

      do {
        let container = try ModelContainer(
          for: LegacyHistorySchema.HistoryItem.self,
          configurations: ModelConfiguration(url: url)
        )
        let context = container.mainContext
        let item = LegacyHistorySchema.HistoryItem()
        item.application = application
        item.firstCopiedAt = firstCopiedAt
        item.lastCopiedAt = lastCopiedAt
        item.numberOfCopies = numberOfCopies
        item.pin = pin
        item.title = title
        item.contents = [
          LegacyHistorySchema.HistoryItemContent(
            type: NSPasteboard.PasteboardType.string.rawValue,
            value: stringValue
          ),
          LegacyHistorySchema.HistoryItemContent(
            type: NSPasteboard.PasteboardType.rtf.rawValue,
            value: rtfValue
          )
        ]
        context.insert(item)

        let another = LegacyHistorySchema.HistoryItem()
        another.title = "second legacy item"
        another.numberOfCopies = 3
        another.contents = [
          LegacyHistorySchema.HistoryItemContent(
            type: NSPasteboard.PasteboardType.string.rawValue,
            value: Data("second".utf8)
          )
        ]
        context.insert(another)
        try context.save()
      }

      do {
        let container = try ModelContainer(for: HistoryItem.self, configurations: ModelConfiguration(url: url))
        let context = container.mainContext
        let items = try context.fetch(FetchDescriptor<HistoryItem>())
        #expect(items.count == 2)
        let item = try #require(items.first { $0.title == title })
        #expect(!item.isProtected)
        #expect(item.application == application)
        #expect(abs(item.firstCopiedAt.timeIntervalSince(firstCopiedAt)) < 0.001)
        #expect(abs(item.lastCopiedAt.timeIntervalSince(lastCopiedAt)) < 0.001)
        #expect(item.numberOfCopies == numberOfCopies)
        #expect(item.pin == pin)
        let contentTypes = Set(item.contents.map(\.type))
        let expectedContentTypes = Set([
          NSPasteboard.PasteboardType.string.rawValue,
          NSPasteboard.PasteboardType.rtf.rawValue
        ])
        #expect(contentTypes == expectedContentTypes)
        let storedString = item.contents.first { $0.type == NSPasteboard.PasteboardType.string.rawValue }
        let storedRTF = item.contents.first { $0.type == NSPasteboard.PasteboardType.rtf.rawValue }
        #expect(storedString?.value == stringValue)
        #expect(storedRTF?.value == rtfValue)

        item.isProtected = true
        try context.save()
      }

      do {
        let container = try ModelContainer(for: HistoryItem.self, configurations: ModelConfiguration(url: url))
        let context = container.mainContext
        let items = try context.fetch(FetchDescriptor<HistoryItem>())
        #expect(items.count == 2)
        let item = try #require(items.first { $0.title == title })
        #expect(item.isProtected)
        #expect(item.application == application)
        #expect(item.numberOfCopies == numberOfCopies)
        #expect(item.pin == pin)
        #expect(item.contents.count == 2)
      }
    }

    @Test("Pinning updates pin order")
    func pinningUpdatesPinOrder() {
      let item = history.add(historyItem("foo"))
      history.togglePin(item)

      #expect(history.pinnedItems == [item])
      #expect(Defaults[.pinOrder].pins == [item.item.pin].compactMap { $0 })
    }

    @Test("Pins without a free key get no shortcuts")
    func noShortcutsForPinWithoutKey() {
      #expect(KeyShortcut.create(character: "").isEmpty)
      #expect(KeyShortcut.create(character: "b").count == 3)
    }

    @Test("Pinning after all shortcuts are assigned")
    func pinningAfterAllShortcutsAreAssigned() async throws {
      let supportedPins = HistoryItem.supportedPins
      for index in 0..<supportedPins.count {
        let item = history.add(historyItem("keyed \(index)"))
        history.togglePin(item)
      }

      #expect(history.availablePins.isEmpty)
      #expect(Set(history.pinnedItems.compactMap(\.item.pin)) == supportedPins)

      let first = history.add(historyItem("first without shortcut"))
      history.togglePin(first)
      let second = history.add(historyItem("second without shortcut"))
      history.togglePin(second)

      #expect(first.item.pin == "")
      #expect(second.item.pin == "")
      #expect(history.pinnedItems.suffix(2) == [first, second])
      #expect(history.unpinnedItems.isEmpty)

      for index in 0...Defaults[.size] {
        history.add(historyItem("unpinned \(index)"))
      }

      let expectedCount = supportedPins.count + 2
      #expect(history.pinnedItems.count == expectedCount)
      try assertStorageCounts(
        items: expectedCount + Defaults[.size],
        contents: expectedCount + Defaults[.size]
      )

      try await history.load()
      #expect(history.pinnedItems.count == expectedCount)
      #expect(
        Set(history.pinnedItems.filter { $0.item.pin == "" }.map(\.title)) ==
        ["first without shortcut", "second without shortcut"]
      )
    }

    @Test("Unpinning updates pin order")
    func unpinningUpdatesPinOrder() {
      let item = history.add(historyItem("foo"))
      history.togglePin(item)
      history.togglePin(item)

      #expect(history.pinnedItems == [])
      #expect(Defaults[.pinOrder].pins == [])
    }

    @Test("Moving pins updates pin order")
    func movingPinsUpdatesPinOrder() {
      let first = history.add(historyItem("foo"))
      let second = history.add(historyItem("bar"))
      history.togglePin(first)
      history.togglePin(second)

      history.movePin(from: IndexSet(integer: 0), to: 2)

      #expect(history.pinnedItems == [second, first])
      #expect(Defaults[.pinOrder].pins == [second.item.pin, first.item.pin].compactMap { $0 })
    }

    @Test("Max size is changed")
    func maxSizeIsChanged() {
      var items: [HistoryItemDecorator] = []
      for index in 0...10 {
        items.append(history.add(historyItem(String(index))))
      }
      Defaults[.size] = 5
      history.add(historyItem("11"))

      #expect(history.items.count == 5)
      #expect(history.items.contains(items[10]))
      #expect(!history.items.contains(items[5]))
    }

    @Test("Re-adding bottom-most pinned item at full capacity")
    func readdingBottomMostPinnedItemAtFullCapacity() {
      // Regression test for a crash when re-copying (invoking) the bottom-most
      // pinned item while history is at full capacity and pins are sorted to the
      // bottom. The stale insert index used to trap with an out-of-bounds insert.
      // Issue link: https://github.com/p0deje/Maccy/issues/1466
      // `pinTo` is restored to its default value(.top) in `deinit`.
      Defaults[.pinTo] = .bottom

      // Pin an item; `history.togglePin` re-sorts `all`, so with `.bottom` the
      // pinned item ends up as the last element.
      let pinned = history.add(historyItem("pinned"))
      history.togglePin(pinned)

      // Fill unpinned history to full capacity.
      for index in 0..<Defaults[.size] {
        history.add(historyItem(String(index)))
      }

      #expect(history.items.last == pinned)

      // Re-copy the pinned item. It is detected as a duplicate, removed and
      // re-inserted while `limitHistorySize` trims an exceeding unpinned item.
      // Before the fix this inserted at a stale, out-of-bounds index and crashed.
      let readded = history.add(historyItem("pinned"))

      #expect(history.items.contains(readded))
      #expect(history.items.filter(\.isPinned).count == 1)
    }

    @Test("Removing")
    func removing() throws {
      let foo = history.add(historyItem("foo"))
      let bar = history.add(historyItem("bar"))
      history.delete(foo)
      #expect(history.items.toArray() == [bar])
      try assertStorageCounts(items: 1, contents: 1)
    }

    @Test("Cleaning up orphaned contents")
    func cleaningUpOrphanedContents() throws {
      let live = history.add(historyItem("live"))
      let liveContent = live.item.contents[0]
      for value in ["orphan-1", "orphan-2"] {
        Storage.shared.context.insert(HistoryItemContent(
          type: NSPasteboard.PasteboardType.string.rawValue,
          value: value.data(using: .utf8)
        ))
      }
      try Storage.shared.context.save()

      #expect(try Storage.shared.cleanupOrphanedContents() == 2)
      #expect(try Storage.shared.cleanupOrphanedContents() == 0)
      #expect(live.item.contents == [liveContent])
      try assertStorageCounts(items: 1, contents: 1)
    }

    @Test("Removing unpersistable contents")
    func removingUnpersistableContents() throws {
      let live = history.add(historyItem("live"))
      live.item.contents.append(HistoryItemContent(
        type: NSPasteboard.PasteboardType.safariWebArchve.rawValue,
        value: Data(repeating: 0x61, count: 1024)
      ))
      try Storage.shared.context.save()

      #expect(try Storage.shared.removeUnpersistableContents() == 1)
      #expect(try Storage.shared.removeUnpersistableContents() == 0)
      #expect(live.item.contents.map(\.type) == [NSPasteboard.PasteboardType.string.rawValue])
      try assertStorageCounts(items: 1, contents: 1)
    }

    private func assertPersistedStorageCounts(
      items: Int,
      contents: Int,
      fileID: String = #fileID,
      filePath: String = #filePath,
      line: Int = #line,
      column: Int = #column
    ) throws {
      let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
      try Storage.shared.context.save()

      // Read through a different context so an uncommitted rollback bug cannot
      // be hidden by the UI context's cached model state.
      let context = ModelContext(Storage.shared.container)
      #expect(
        try context.fetchCount(FetchDescriptor<HistoryItem>()) == items,
        sourceLocation: sourceLocation
      )
      #expect(
        try context.fetchCount(FetchDescriptor<HistoryItemContent>()) == contents,
        sourceLocation: sourceLocation
      )
    }

    private func assertStorageCounts(
      items: Int,
      contents: Int,
      orphaned: Int = 0,
      fileID: String = #fileID,
      filePath: String = #filePath,
      line: Int = #line,
      column: Int = #column
    ) throws {
      let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
      let context = Storage.shared.context
      context.processPendingChanges()
      try context.save()
      #expect(
        try context.fetchCount(FetchDescriptor<HistoryItem>()) == items,
        sourceLocation: sourceLocation
      )
      #expect(
        try context.fetchCount(FetchDescriptor<HistoryItemContent>()) == contents,
        sourceLocation: sourceLocation
      )
      #expect(
        try context.fetchCount(FetchDescriptor<HistoryItemContent>(
          predicate: #Predicate { $0.item == nil }
        )) == orphaned,
        sourceLocation: sourceLocation
      )
    }

    private func temporaryDatabaseLocation() throws -> (URL, URL) {
      let directory = FileManager.default.temporaryDirectory
        .appending(path: "MaccyProtectedTests-\(UUID().uuidString)", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      return (directory, directory.appending(path: "Storage.sqlite"))
    }

    private func historyItem(_ value: String, persisted: Bool = true) -> HistoryItem {
      let contents = [
        HistoryItemContent(
          type: NSPasteboard.PasteboardType.string.rawValue,
          value: value.data(using: .utf8)
        )
      ]
      let item = HistoryItem()
      if persisted {
        Storage.shared.context.insert(item)
      }
      item.contents = contents
      item.numberOfCopies = 1
      item.title = item.generateTitle()

      return item
    }
  }
}

enum LegacyHistorySchema {
  @Model
  final class HistoryItem {
    var application: String?
    var firstCopiedAt: Date = Date.now
    var lastCopiedAt: Date = Date.now
    var numberOfCopies: Int = 1
    var pin: String?
    var title = ""

    @Relationship(deleteRule: .cascade, inverse: \HistoryItemContent.item)
    var contents: [HistoryItemContent] = []

    init() {}
  }

  @Model
  final class HistoryItemContent {
    var type: String = ""
    var value: Data?

    @Relationship
    var item: HistoryItem?

    init(type: String, value: Data? = nil) {
      self.type = type
      self.value = value
    }
  }
}
