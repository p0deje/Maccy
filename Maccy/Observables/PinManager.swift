import Defaults
import Observation
import SwiftUI

struct PinOrder: Codable, Equatable, Defaults.Serializable {
  var pins: [String]

  init(pins: [String] = []) {
    self.pins = Self.uniquePins(pins)
  }

  mutating func reconcile(with assignedPins: [String]) {
    let assignedPins = Self.uniquePins(assignedPins)
    let assignedPinSet = Set(assignedPins)
    pins = Self.uniquePins(pins).filter { assignedPinSet.contains($0) }

    for pin in assignedPins where !pins.contains(pin) {
      pins.append(pin)
    }
  }

  mutating func append(_ pin: String) {
    guard !pin.isEmpty, !pins.contains(pin) else { return }
    pins.append(pin)
  }

  mutating func remove(_ pin: String) {
    pins.removeAll { $0 == pin }
  }

  mutating func replace(_ oldPin: String?, with newPin: String) {
    guard !newPin.isEmpty else { return }

    pins.removeAll { $0 == newPin }
    if let oldPin, let index = pins.firstIndex(of: oldPin) {
      pins[index] = newPin
    } else {
      pins.append(newPin)
    }
  }

  private static func uniquePins(_ pins: [String]) -> [String] {
    var uniquePins: [String] = []
    for pin in pins where !pin.isEmpty && !uniquePins.contains(pin) {
      uniquePins.append(pin)
    }
    return uniquePins
  }
}

@Observable
final class PinManager {
  private(set) var pinnedItems: [HistoryItemDecorator] = []

  var availablePins: [String] {
    let assignedPins = Set(pinnedItems.compactMap(\.item.pin))
    return HistoryItem.supportedPins.subtracting(assignedPins).sorted()
  }

  func load(from items: [HistoryItemDecorator]) {
    pinnedItems = items.filter(\.isPinned)
    reconcileOrder()
    sortPinnedItems()
  }

  func toggle(_ item: HistoryItemDecorator) {
    if item.isPinned {
      unpin(item)
    } else {
      pin(item)
    }
  }

  func add(_ item: HistoryItemDecorator) {
    guard item.isPinned, !pinnedItems.contains(item) else { return }
    pinnedItems.append(item)
    reconcileOrder()
    sortPinnedItems()
  }

  func replace(_ oldItem: HistoryItemDecorator, with newItem: HistoryItemDecorator) {
    guard newItem.isPinned else { return }
    guard let index = pinnedItems.firstIndex(of: oldItem) else {
      add(newItem)
      return
    }
    pinnedItems[index] = newItem
  }

  func updatePin(of item: HistoryItemDecorator, to pin: String) {
    guard HistoryItem.supportedPins.contains(pin) else { return }
    guard item.item.pin != pin else { return }
    guard !pinnedItems.contains(where: { $0 != item && $0.item.pin == pin })
    else { return }

    let oldPin = item.item.pin
    item.item.pin = pin

    if !pinnedItems.contains(item) {
      pinnedItems.append(item)
    }

    var order = Defaults[.pinOrder]
    order.replace(oldPin, with: pin)
    Defaults[.pinOrder] = order
    sortPinnedItems()
  }

  func remove(_ item: HistoryItemDecorator) {
    guard let pin = item.item.pin else { return }

    pinnedItems.removeAll { $0 == item }
    if !pinnedItems.contains(where: { $0.item.pin == pin }) {
      var order = Defaults[.pinOrder]
      order.remove(pin)
      Defaults[.pinOrder] = order
    }
  }

  func removeAll() {
    pinnedItems.removeAll()
    Defaults[.pinOrder] = PinOrder()
  }

  func move(from source: IndexSet, to destination: Int) {
    pinnedItems.moveElements(from: source, to: destination)
    Defaults[.pinOrder] = PinOrder(pins: pinnedItems.compactMap(\.item.pin))
  }

  private func pin(_ item: HistoryItemDecorator) {
    guard item.isUnpinned, let pin = availablePins.randomElement() else {
      return
    }

    item.item.pin = pin
    pinnedItems.append(item)

    var order = Defaults[.pinOrder]
    order.append(pin)
    Defaults[.pinOrder] = order
    sortPinnedItems()
  }

  private func unpin(_ item: HistoryItemDecorator) {
    guard let pin = item.item.pin else { return }

    item.item.pin = nil
    pinnedItems.removeAll { $0 == item }

    if !pinnedItems.contains(where: { $0.item.pin == pin }) {
      var order = Defaults[.pinOrder]
      order.remove(pin)
      Defaults[.pinOrder] = order
    }
  }

  private func reconcileOrder() {
    var order = Defaults[.pinOrder]
    order.reconcile(with: pinnedItems.compactMap(\.item.pin))
    Defaults[.pinOrder] = order
  }

  private func sortPinnedItems() {
    let originalIndexes = Dictionary(
      uniqueKeysWithValues: pinnedItems.enumerated().map {
        ($0.element.id, $0.offset)
      }
    )
    let order = Defaults[.pinOrder].pins

    pinnedItems.sort { lhs, rhs in
      let lhsIndex =
        lhs.item.pin.flatMap { order.firstIndex(of: $0) } ?? Int.max
      let rhsIndex =
        rhs.item.pin.flatMap { order.firstIndex(of: $0) } ?? Int.max

      if lhsIndex != rhsIndex {
        return lhsIndex < rhsIndex
      }

      return (originalIndexes[lhs.id] ?? 0) < (originalIndexes[rhs.id] ?? 0)
    }
  }
}
