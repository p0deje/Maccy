import Defaults
import SwiftUI

struct HistoryItemView: View {
  @Bindable var item: HistoryItemDecorator
  var previous: HistoryItemDecorator?
  var next: HistoryItemDecorator?
  var index: Int

  private var selectionAppearance: SelectionAppearance {
    let previousSelected = previous?.isSelected ?? false
    let nextSelected = next?.isSelected ?? false
    switch (previousSelected, nextSelected) {
    case (true, false):
      return .topConnection
    case (false, true):
      return .bottomConnection
    case (true, true):
      return .topBottomConnection
    default:
      return .none
    }
  }

  @Default(.showHexColorSwatch) private var showHexColorSwatch
  @Environment(AppState.self) private var appState

  private var colorSwatchImage: NSImage? {
    guard showHexColorSwatch else { return nil }
    return ColorImage.from(item.title)
  }

  private var shouldShowThumbnailImage: Bool {
    item.thumbnailImage != nil && !item.hasAlias
  }

  private func performSelect() {
    if NSEvent.modifierFlags.contains(.command) && appState.multiSelectionEnabled {
      appState.navigator.addToSelection(item: item)
    } else {
      let flags = NSEvent.ModifierFlags.currentModifierFlags
      Task {
        appState.history.select(item, flags: flags)
      }
    }
  }

  var body: some View {
    ListItemView(
      id: item.id,
      selectionId: item.id,
      appIcon: item.applicationImage,
      image: shouldShowThumbnailImage ? item.thumbnailImage : nil,
      accessoryImage: shouldShowThumbnailImage ? nil : colorSwatchImage,
      attributedTitle: item.attributedTitle,
      titleIconSystemName: item.hasAlias ? "tag.fill" : nil,
      titleIconHelp: item.hasAlias
        ? NSLocalizedString(
          "AliasIconTooltip",
          tableName: "PinsSettings",
          value: "Alias: This item displays a custom name instead of the original clipboard content.",
          comment: "Tooltip shown when hovering the alias icon in the history row"
        )
        : nil,
      shortcuts: item.shortcuts,
      isSelected: item.isSelected,
      selectionIndex: item.multiSelectionIndex,
      selectionAppearance: selectionAppearance,
      accessibilityLabel: item.accessibilityLabel
    ) {
      Text(verbatim: item.title)
    }
    .accessibilityIdentifier("copy-history-item")
    .buttonAction(performSelect)
    .contextMenu {
      Button(item.isPinned ? "Unpin" : "Pin") {
        appState.prepareForHistoryItemAction(item)
        appState.history.togglePin(item)
      }

      Button(item.hasAlias ? "Edit Alias..." : "Set Alias...") {
        appState.startEditing(item)
      }

      if item.hasAlias {
        Button("Remove Alias") {
          appState.prepareForHistoryItemAction(item)
          appState.history.setAlias(item, to: nil)
        }
      }

      Divider()

      Button("Delete", role: .destructive) {
        appState.prepareForHistoryItemAction(item)
        appState.history.delete(item)
      }
    }
    .onAppear {
      item.ensureThumbnailImage()
    }
    .accessibilityAction(named: Text(item.isPinned ? "history_item_unpin_action" : "history_item_pin_action")) {
      appState.prepareForHistoryItemAction(item)
      appState.history.togglePin(item)
    }
    .accessibilityAction(named: Text("history_item_delete_action")) {
      appState.prepareForHistoryItemAction(item)
      appState.history.delete(item)
    }
  }
}
