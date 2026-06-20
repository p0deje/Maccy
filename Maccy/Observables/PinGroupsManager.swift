import Foundation
import Observation
import SwiftData

@Observable
class PinGroupsManager {
  static let shared = PinGroupsManager()

  var groups: [PinGroup] = []
  var expandedGroupIDs: Set<PersistentIdentifier> = []

  /// The default group — always expanded by default.
  /// Other groups start collapsed and expand on demand.
  var defaultGroup: PinGroup? {
    groups.first
  }

  @MainActor
  func load() async throws {
    let descriptor = FetchDescriptor<PinGroup>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
    groups = try Storage.shared.context.fetch(descriptor)

    // If no groups exist, create a default "General" group
    if groups.isEmpty {
      let general = PinGroup(name: NSLocalizedString("DefaultGroupName", tableName: "PinGroups", comment: ""), sortOrder: 0)
      Storage.shared.context.insert(general)
      try? Storage.shared.context.save()
      groups = [general]
    }

    // Default group starts expanded
    if let defaultGroup {
      expandedGroupIDs.insert(defaultGroup.persistentModelID)
    }
  }

  @MainActor
  func createGroup(name: String) -> PinGroup {
    let maxOrder = groups.map(\.sortOrder).max() ?? 0
    let group = PinGroup(name: name, sortOrder: maxOrder + 1)
    Storage.shared.context.insert(group)
    try? Storage.shared.context.save()

    // Reload to get persistent ID
    groups.append(group)
    // New groups start collapsed (consistent with "other groups are collapsed by default")
    return group
  }

  @MainActor
  func renameGroup(_ group: PinGroup, to name: String) {
    group.name = name
    try? Storage.shared.context.save()
  }

  @MainActor
  func deleteGroup(_ group: PinGroup) {
    // Move items in this group to ungrouped (pin stays, group goes to nil)
    for item in group.items {
      item.pinGroup = nil
    }
    Storage.shared.context.delete(group)
    try? Storage.shared.context.save()
    groups.removeAll { $0.persistentModelID == group.persistentModelID }
    expandedGroupIDs.remove(group.persistentModelID)
  }

  @MainActor
  func moveItemToGroup(_ item: HistoryItem, group: PinGroup) {
    item.pinGroup = group
    try? Storage.shared.context.save()
  }

  @MainActor
  func removeItemFromGroup(_ item: HistoryItem) {
    item.pinGroup = nil
    try? Storage.shared.context.save()
  }

  func isExpanded(_ group: PinGroup) -> Bool {
    expandedGroupIDs.contains(group.persistentModelID)
  }

  func toggleExpanded(_ group: PinGroup) {
    if expandedGroupIDs.contains(group.persistentModelID) {
      expandedGroupIDs.remove(group.persistentModelID)
    } else {
      expandedGroupIDs.insert(group.persistentModelID)
    }
  }

  /// Pin the item: assign a pin key + add to the given group.
  @MainActor
  func pinItem(_ item: HistoryItem, to group: PinGroup?) {
    // If not already pinned, assign a pin key
    if item.pin == nil {
      item.pin = HistoryItem.randomAvailablePin
    }
    item.pinGroup = group ?? defaultGroup
    try? Storage.shared.context.save()
  }

  /// Unpin the item: remove pin key and group association.
  @MainActor
  func unpinItem(_ item: HistoryItem) {
    item.pin = nil
    item.pinGroup = nil
    try? Storage.shared.context.save()
  }
}
