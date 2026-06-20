import SwiftData
import SwiftUI

struct PinsView: View {
  @Environment(AppState.self) private var appState
  @Environment(PinGroupsManager.self) private var pinGroupsManager

  var items: [HistoryItemDecorator]

  private var groupedItems: [(group: PinGroup?, items: [HistoryItemDecorator])] {
    let pinned = items.filter(\.isPinned)
    var result: [(group: PinGroup?, items: [HistoryItemDecorator])] = []
    var seen = Set<UUID>()

    // Group items by their pinGroup, respecting group sort order
    let groupsInOrder = pinGroupsManager.groups
    for group in groupsInOrder {
      let groupItems = pinned.filter { $0.groupID == group.persistentModelID }
      if !groupItems.isEmpty {
        result.append((group: group, items: groupItems))
        groupItems.forEach { seen.insert($0.id) }
      }
    }

    // Items with pin but no group (legacy / removed group)
    let ungrouped = pinned.filter { item in
      !seen.contains(item.id)
    }
    if !ungrouped.isEmpty {
      result.append((group: nil, items: ungrouped))
    }

    return result
  }

  var body: some View {
    if groupedItems.count <= 1, let firstGroup = groupedItems.first {
      // Single group: no header needed, just show items (backward compatible)
      MultipleSelectionListView(items: firstGroup.items) { previous, item, next, index in
        HistoryItemView(item: item, previous: previous, next: next, index: index)
      }
    } else {
      // Multiple groups: show headers with expand/collapse
      ForEach(Array(groupedItems.enumerated()), id: \.offset) { _, section in
        if let group = section.group {
          let expanded = pinGroupsManager.isExpanded(group)
          PinGroupHeaderView(
            group: group,
            isExpanded: expanded,
            toggle: { pinGroupsManager.toggleExpanded(group) }
          )

          if expanded {
            MultipleSelectionListView(items: section.items) { previous, item, next, index in
              HistoryItemView(item: item, previous: previous, next: next, index: index)
            }
          }
        } else {
          // Ungrouped pins: show without header
          MultipleSelectionListView(items: section.items) { previous, item, next, index in
            HistoryItemView(item: item, previous: previous, next: next, index: index)
          }
        }
      }
    }
  }
}
