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

  private var canSplit: Bool {
    !item.hasImage && !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .trailing) {
        ListItemView(
          id: item.id,
          selectionId: item.id,
          appIcon: item.applicationImage,
          image: item.thumbnailImage,
          accessoryImage: item.thumbnailImage != nil ? nil : colorSwatchImage,
          attributedTitle: item.attributedTitle,
          shortcuts: item.shortcuts,
          isSelected: item.isSelected,
          selectionIndex: item.multiSelectionIndex,
          selectionAppearance: selectionAppearance,
          trailingActionSpacing: canSplit && item.isSelected ? 30 : 0,
          accessibilityLabel: item.accessibilityLabel
        ) {
          Text(verbatim: item.title)
        }
        .accessibilityIdentifier("copy-history-item")
        .buttonAction(performSelect)
        .onAppear {
          item.ensureThumbnailImage()
        }
        .accessibilityAction(named: Text("split_action")) {
          appState.preview.openSplit(for: item)
        }
        .accessibilityAction(named: Text(item.isPinned ? "history_item_unpin_action" : "history_item_pin_action")) {
          appState.history.togglePin(item)
        }
        .accessibilityAction(named: Text("history_item_delete_action")) {
          appState.history.delete(item)
        }

        if canSplit && item.isSelected {
          Button {
            appState.preview.openSplit(for: item)
          } label: {
            Image(systemName: "text.badge.plus")
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.white)
          .frame(width: 22, height: Popup.itemHeight)
          .padding(.trailing, 8)
          .help(String(localized: "split_action"))
          .accessibilityLabel(Text("split_action"))
        }

      }
    }
  }
}
