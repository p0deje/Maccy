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

  @Default(.showHexColorSwatch) private var showHexColorSwatch
  @Environment(AppState.self) private var appState

  private var colorSwatchImage: NSImage? {
    guard showHexColorSwatch else { return nil }
    return ColorImage.from(item.title)
  }

  var body: some View {
    listItem
      .onTapGesture {
        if NSEvent.modifierFlags.contains(.command) && appState.multiSelectionEnabled {
          appState.navigator.addToSelection(item: item)
        } else if item.isPinned {
          copyPinnedItem()
        } else {
          selectItem()
        }
      }
      .contextMenu {
        Menu("Pin to Topic...") {
          ForEach(allTopics, id: \.self) { targetTopic in
            Button(targetTopic) {
              if item.isUnpinned {
                item.togglePin()
              }
              item.topic = (targetTopic == "Uncategorized") ? nil : targetTopic
            }
          }
        }
      }
  }

  private var listItem: some View {
    ListItemView(
      id: item.id,
      selectionId: item.id,
      appIcon: item.applicationImage,
      image: item.thumbnailImage,
      accessoryImage: item.thumbnailImage != nil ? nil : colorSwatchImage,
      attributedTitle: item.attributedTitle,
      shortcuts: item.shortcuts,
      isSelected: item.isSelected,
      selectionIndex: visualIndex,
      selectionAppearance: selectionAppearance
    ) {
      Text(verbatim: item.title)
    }
    .onAppear {
      item.ensureThumbnailImage()
    }
  }

  @AppStorage("customTopics") private var customTopicsData: Data = Data()
  private var allTopics: [String] {
    let itemTopics = Set(appState.history.pinnedItems.compactMap { $0.topic })
    let custom = (try? JSONDecoder().decode([String].self, from: customTopicsData)) ?? []
    return itemTopics.union(custom).union(["Uncategorized"]).sorted()
  }

  private func selectItem() {
    Task { @MainActor in
      appState.history.select(item)
    }
  }

  private func copyPinnedItem() {
    appState.navigator.select(item: item)
    Clipboard.shared.copy(
      item.item,
      removeFormatting: Defaults[.removeFormattingByDefault]
    )
  }
}
