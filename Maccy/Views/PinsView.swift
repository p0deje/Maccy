import SwiftUI
import UniformTypeIdentifiers

private enum PinReorderDrag {
  static let contentType = UTType(exportedAs: "org.p0deje.Maccy.pin-reorder")
}

struct PinsView: View {
  @Environment(AppState.self) private var appState

  var items: [HistoryItemDecorator]
  @State private var draggedItems: [HistoryItemDecorator] = []

  private var isDragAndDropEnabled: Bool {
    appState.history.searchQuery.isEmpty
  }

  var body: some View {
    LazyVStack(spacing: 0) {
      if isDragAndDropEnabled {
        MultipleSelectionListView(items: items) { prev, item, next, index in
          HistoryItemView(
            item: item,
            previous: prev,
            next: next,
            index: index
          )
          .draggableItem(item)
        }
        .draggableContainer(
          items: items,
          contentType: PinReorderDrag.contentType,
          dragPreview: { draggedItems in
            MultipleSelectionListView(items: draggedItems) { prev, item, next, index in
              HistoryItemView(
                item: item,
                previous: prev,
                next: next,
                index: index
              )
            }
            .background(.regularMaterial)
            .clipShape(SelectionAppearance.none.rect(cornerRadius: Popup.cornerRadius))
          },
          selection: Binding(
            get: { appState.navigator.selection },
            set: { appState.navigator.selection = $0 }
          ),
          draggedItems: $draggedItems,
          moveAction: { source, destination in
            withAnimation(.default.speed(2)) {
              move(from: source, to: destination)
            }
          }
        )
      } else {
        MultipleSelectionListView(items: items) { prev, item, next, index in
          HistoryItemView(
            item: item,
            previous: prev,
            next: next,
            index: index
          )
        }
      }
    }
    .excludeFromWindowMovableByBackground()
  }

  func move(from source: IndexSet, to destination: Int) {
    appState.history.movePin(from: source, to: destination)
  }
}
