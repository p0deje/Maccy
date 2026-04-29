import Defaults
import SwiftUI

struct HistoryItemView: View {
  @Bindable var item: HistoryItemDecorator
  var previous: HistoryItemDecorator?
  var next: HistoryItemDecorator?
  var index: Int

  private var visualIndex: Int? {
    if appState.navigator.isMultiSelectInProgress && item.selectionIndex >= 0 {
      return item.selectionIndex
    }
    return nil
  }

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

  @Environment(AppState.self) private var appState

  var body: some View {
    ListItemView(
      id: item.id,
      selectionId: item.id,
      appIcon: item.applicationImage,
      image: item.thumbnailImage,
      accessoryImage: item.thumbnailImage != nil ? nil : ColorImage.from(item.title),
      attributedTitle: item.attributedTitle,
      shortcuts: item.shortcuts,
      isSelected: item.isSelected,
      selectionIndex: visualIndex,
      selectionAppearance: selectionAppearance,
      hoverSelectionEnabled: false
    ) {
      Text(verbatim: item.displayTitle)
    }
    .onHover { hovering in
      guard hovering else { return }

      if appState.popup.suppressesHoverSelection {
        appState.navigator.hoverSelectionWhileKeyboardNavigating = item.id
        return
      }

      if !appState.navigator.isKeyboardNavigating && !appState.navigator.isMultiSelectInProgress {
        appState.navigator.selectWithoutScrolling(item: item)
      } else {
        appState.navigator.hoverSelectionWhileKeyboardNavigating = item.id
      }
    }
    .onAppear {
      // Fast path: only decodes pre-rendered thumbnailData. No contents fault.
      item.ensureThumbnailImage()
      if item.isPinned {
        item.startObservationIfNeeded()
      }
      // `index` is this row's position in the parent's unpinned array, so
      // we can do a constant-time "are we near the end?" check inside.
      appState.history.itemDidAppear(at: index)
    }
    .onDisappear {
      item.cancelSelectionLoad()
      item.cleanupPreviewImage()
    }
    .onTapGesture {
      if NSEvent.modifierFlags.contains(.command) && appState.multiSelectionEnabled {
        appState.navigator.addToSelection(item: item)
      } else {
        Task {
          appState.history.select(item)
        }
      }
    }
  }
}
