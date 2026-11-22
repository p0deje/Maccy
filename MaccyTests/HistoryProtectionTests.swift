import AppKit
import Testing
import Defaults
import SwiftData
import SwiftUI
@testable import Maccy

extension SharedStateTests.HistoryTests {
  @Test("Duplicate copy inherits protected state")
  func duplicateCopyInheritsProtectedState() throws {
    let first = history.add(historyItem("protected duplicate"))
    history.toggleProtection(first)

    let duplicate = history.add(historyItem("protected duplicate"))

    #expect(duplicate.isProtected)
    #expect(history.items.toArray() == [duplicate])
    try assertStorageCounts(items: 1, contents: 1)
  }

  @Test("Preview text input takes keyboard commands from history navigation")
  func previewTextInputUsesTextEditingKeys() {
    let textView = NSTextView()
    textView.isEditable = false

    #expect(PreviewTextKeyboardPolicy.isPreviewTextInput(textView))
    #expect(!PreviewTextKeyboardPolicy.isPreviewTextInput(NSView()))
    textView.isEditable = true
    #expect(!PreviewTextKeyboardPolicy.isPreviewTextInput(textView))

    #expect(PreviewTextKeyboardPolicy.handlesWindowCommand(.close))
    #expect(PreviewTextKeyboardPolicy.handlesWindowCommand(.openPreferences))
    #expect(PreviewTextKeyboardPolicy.handlesWindowCommand(.togglePreview))
    #expect(!PreviewTextKeyboardPolicy.handlesWindowCommand(.moveToNext))
    #expect(!PreviewTextKeyboardPolicy.handlesWindowCommand(.selectCurrentItem))
    #expect(PreviewTextKeyboardPolicy.action(for: .close) == .closePopup)
    #expect(PreviewTextKeyboardPolicy.action(for: .openPreferences) == .openPreferences)
    #expect(PreviewTextKeyboardPolicy.action(for: .togglePreview) == .togglePreview)
    #expect(PreviewTextKeyboardPolicy.action(for: .moveToNext) == .passToTextView)
    #expect(PreviewTextKeyboardPolicy.action(for: .selectCurrentItem) == .passToTextView)
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

  @Test("Closing panel clears storage error")
  func closingPanelClearsStorageError() {
    let appState = AppState.shared
    let previousError = appState.storageErrorMessage
    defer { appState.storageErrorMessage = previousError }

    appState.storageErrorMessage = "retry"
    let panel = FloatingPanel(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      onClose: {},
      view: { EmptyView() }
    )

    panel.close()

    #expect(appState.storageErrorMessage == nil)
  }

  @Test("Batch protection rolls back every item when persistence fails")
  func batchProtectionRollsBackWhenPersistenceFails() {
    struct SimulatedSaveError: Error {}

    let first = history.add(historyItem("batch first"))
    let second = history.add(historyItem("batch second"))
    let succeeded = history.toggleProtection([first, second]) {
      throw SimulatedSaveError()
    }

    #expect(!succeeded)
    #expect(!first.isProtected)
    #expect(!second.isProtected)
  }

  @Test("Batch protection saves once")
  func batchProtectionSavesOnce() {
    let first = history.add(historyItem("batch save first"))
    let second = history.add(historyItem("batch save second"))
    var saves = 0
    let succeeded = history.toggleProtection([first, second]) {
      saves += 1
      try Storage.shared.context.save()
    }

    #expect(succeeded)
    #expect(saves == 1)
    #expect(first.isProtected)
    #expect(second.isProtected)
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

  @Test("Search orders pins before protected items and history")
  func searchOrdersPinsBeforeProtectedItemsAndHistory() {
    history.searchQuery = ""
    let older = history.add(historyItem("web older result"))
    let protectedMatch = history.add(historyItem("web protected result"))
    history.toggleProtection(protectedMatch)
    let pinnedMatch = history.add(historyItem("web pinned result"))
    history.togglePin(pinnedMatch)

    Defaults[.pinTo] = .top
    performSearch("web")

    #expect(history.items.toArray() == [pinnedMatch, protectedMatch, older])
    // Pins retain their pin shortcuts; protected matches take the leading
    // numeric shortcuts among non-pinned search results.
    #expect(protectedMatch.shortcuts.first?.key == .one)
    #expect(older.shortcuts.first?.key == .two)

    performSearch("")
    #expect(history.items.toArray() == [pinnedMatch, protectedMatch, older])
  }

  @Test("Search preserves pin order before protected and ordinary results")
  func searchPreservesPinOrderBeforeOtherResults() {
    history.searchQuery = ""
    let ordinary = history.add(historyItem("web ordinary result"))
    let protectedMatch = history.add(historyItem("web protected result"))
    history.toggleProtection(protectedMatch)
    let firstPin = history.add(historyItem("web first pin"))
    history.updatePin(firstPin.item, to: "b")
    let secondPin = history.add(historyItem("web second pin"))
    history.updatePin(secondPin.item, to: "c")

    performSearch("web")

    #expect(history.items.toArray() == [firstPin, secondPin, protectedMatch, ordinary])
    performSearch("")
  }

  @Test("Throttled search selects the first pinned match for Enter")
  func throttledSearchSelectsPinnedMatch() async throws {
    performSearch("")
    let protectedMatch = history.add(historyItem("web protected match"))
    history.toggleProtection(protectedMatch)
    history.add(historyItem("web newer ordinary match"))
    let pinnedMatch = history.add(historyItem("web pinned match"))
    history.togglePin(pinnedMatch)
    Defaults[.pinTo] = .top

    history.searchQuery = "nonmatching"
    history.searchQuery = "we"
    history.searchQuery = "web"
    for _ in 0..<50 {
      if AppState.shared.navigator.leadHistoryItem == pinnedMatch {
        break
      }
      try await Task.sleep(for: .milliseconds(20))
    }

    #expect(AppState.shared.navigator.leadHistoryItem == pinnedMatch)
    #expect(history.items.first == pinnedMatch)
    #expect(protectedMatch.shortcuts.first?.key == .one)

    history.searchQuery = ""
    try await Task.sleep(for: .milliseconds(250))
    #expect(history.protectedItems.isEmpty)
    #expect(history.items.first == pinnedMatch)
    AppState.shared.navigator.select(item: nil)
  }

  @Test("Search prioritizes pins regardless of their normal position")
  func searchPrioritizesPinsRegardlessOfNormalPosition() {
    history.searchQuery = ""
    let unrelated = history.add(historyItem("zzz unrelated"))
    let older = history.add(historyItem("web older result"))
    let protectedMatch = history.add(historyItem("web protected result"))
    history.toggleProtection(protectedMatch)
    let pinnedMatch = history.add(historyItem("web pinned result"))
    history.togglePin(pinnedMatch)

    // These tests default to pinTo == .bottom: history leads, pins trail.
    performSearch("web")

    #expect(history.items.toArray() == [pinnedMatch, protectedMatch, older])
    #expect(!history.items.contains(unrelated))

    // Leave a clean query: the serialized suite shares one History singleton,
    // and a retained query would leak into the next test's assertions.
    performSearch("")
  }

  @Test("Pinned protected item stays in the pins group during search")
  func pinnedProtectedItemStaysInPinsDuringSearch() {
    history.searchQuery = ""
    let both = history.add(historyItem("web both markers"))
    history.togglePin(both)
    history.toggleProtection(both)
    let plain = history.add(historyItem("web plain result"))

    performSearch("web")

    // Pin takes priority over protection; the item must surface once in the
    // pins group, followed by protected and ordinary results.
    #expect(history.items.toArray() == [both, plain])
    #expect(history.protectedItems.isEmpty)
    #expect(history.unpinnedItems == [plain])
    #expect(history.pinnedItems == [both])

    // Leave a clean query for the next test in the serialized suite.
    performSearch("")
  }

  @Test("Protecting an item during search moves it to the protected group")
  func protectingDuringSearchRegroupsItem() {
    history.searchQuery = ""
    let older = history.add(historyItem("web regroup older"))
    let newer = history.add(historyItem("web regroup newer"))

    performSearch("web")
    #expect(history.unpinnedItems == [newer, older])
    #expect(history.protectedItems.isEmpty)

    history.toggleProtection(older)

    // The freshly protected match must surface in the protected group at once.
    #expect(history.protectedItems == [older])
    #expect(history.unpinnedItems == [newer])
    #expect(history.items.toArray() == [older, newer])
    #expect(older.shortcuts.first?.key == .one)

    history.toggleProtection(older)

    #expect(history.protectedItems.isEmpty)
    #expect(history.unpinnedItems == [newer, older])
    #expect(history.items.toArray() == [newer, older])

    // Leave a clean query for the next test in the serialized suite.
    performSearch("")
  }

  @Test("Pinning an item during search keeps it visible in the pins group")
  func pinningDuringSearchKeepsItemVisible() {
    history.searchQuery = ""
    let match = history.add(historyItem("web pin target"))

    performSearch("web")
    #expect(history.items.toArray() == [match])

    history.updatePin(match.item, to: "b")

    #expect(history.pinnedItems == [match])
    #expect(history.unpinnedItems.isEmpty)
    #expect(history.protectedItems.isEmpty)
    #expect(history.items.toArray() == [match])

    // Leave a clean query for the next test in the serialized suite.
    performSearch("")
  }

  @Test("Toggling pin during search preserves the query and result order")
  func togglingPinDuringSearchPreservesQueryAndResultOrder() {
    history.searchQuery = ""
    let protectedMatch = history.add(historyItem("web protected target"))
    history.toggleProtection(protectedMatch)
    let ordinary = history.add(historyItem("web ordinary target"))

    performSearch("web")
    #expect(history.items.toArray() == [protectedMatch, ordinary])

    history.togglePin(ordinary)

    #expect(history.searchQuery == "web")
    #expect(history.items.toArray() == [ordinary, protectedMatch])

    history.togglePin(ordinary)

    #expect(history.searchQuery == "web")
    #expect(history.items.toArray() == [protectedMatch, ordinary])
    performSearch("")
  }

  @Test("Unpinning a protected item during search moves it below pins")
  func unpinningProtectedItemDuringSearchMovesItBelowPins() {
    history.searchQuery = ""
    let both = history.add(historyItem("web both target"))
    history.togglePin(both)
    history.toggleProtection(both)
    let pin = history.add(historyItem("web pin target"))
    history.updatePin(pin.item, to: "b")

    performSearch("web")
    #expect(history.pinnedItems == [both, pin])
    #expect(history.items.toArray() == [both, pin])
    #expect(history.protectedItems.isEmpty)

    history.togglePin(both)

    #expect(history.searchQuery == "web")
    #expect(history.items.toArray() == [pin, both])
    #expect(history.protectedItems == [both])
    performSearch("")
  }

  /// Search updates normally run through History's throttler, which the test
  /// runner's main thread does not service mid-test; drive them synchronously.
  @MainActor
  private func performSearch(_ query: String) {
    history.searchQuery = query
    history.updateSearchResults()
  }

}
