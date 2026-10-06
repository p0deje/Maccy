import SwiftUI
import UniformTypeIdentifiers

typealias Reorderable = Identifiable & Equatable

@available(macOS 27.0, *)
private struct NativeDraggableContainerModifier<Item: Reorderable>: ViewModifier where Item.ID: Sendable {
  let items: [Item]
  @Binding var selection: Selection<Item>
  @Binding var draggedItems: [Item]

  let moveAction: (IndexSet, Int) -> Void

  func body(content: Content) -> some View {
    content
      .reorderContainer(for: Item.self, move: move)
      .dragContainerSelection(items.filter { selection.items.contains($0) }.map(\.id))
      .onDragSessionUpdated { session in
        switch session.phase {
        case .initial, .active:
          let identifiers = Set(session.draggedItemIDs(for: Item.ID.self))
          draggedItems = items.filter { identifiers.contains($0.id) }
          AppState.shared.navigator.isDragAndDropInProgress = true
        case .ended, .dataTransferCompleted:
          resetDragState()
        default:
          break
        }
      }
      .onDisappear {
        resetDragState()
      }
  }

  private func move(_ difference: ReorderDifference<Item.ID, ReorderableSingleCollectionIdentifier>) {
    let identifiers = Set(difference.sources)
    let source = IndexSet(items.indices.filter { identifiers.contains(items[$0].id) })
    guard !source.isEmpty else { return }

    let destination: Int
    switch difference.destination.position {
    case .before(let identifier):
      guard let index = items.firstIndex(where: { $0.id == identifier }) else { return }
      destination = index
    case .end:
      destination = items.count
    }

    moveAction(source, destination)
  }

  private func resetDragState() {
    draggedItems = []
    AppState.shared.navigator.isDragAndDropInProgress = false
  }
}

private struct DraggableContainerModifier<Item: Reorderable, DragPreview: View>: ViewModifier {
  let items: [Item]
  let contentType: UTType
  let dragPreview: ([Item]) -> DragPreview
  @Binding var selection: Selection<Item>
  @Binding var draggedItems: [Item]

  let moveAction: (IndexSet, Int) -> Void

  @State private var active: Item?
  @State private var lastDropPosition: DropPosition<Item.ID>?

  func body(content: Content) -> some View {
    content
      .environment(\.reorderableDragContext, context)
      .onChange(of: active) {
        if active == nil {
          resetDragState()
        }
      }
      .onDisappear {
        resetDragState()
      }
  }

  private var context: ReorderableDragContext {
    ReorderableDragContext(
      contentType: contentType,
      isDragged: isDragged,
      dragPreview: preview,
      startDrag: startDrag,
      resetDragState: resetDragState,
      move: move
    )
  }

  private func isDragged(_ item: Any) -> Bool {
    guard let item = item as? Item else { return false }
    return draggedItems.contains(item)
  }

  private func preview(for item: Any) -> AnyView {
    guard let item = item as? Item else { return AnyView(EmptyView()) }
    return AnyView(dragPreview(itemsBeingDragged(startingWith: item)))
  }

  private func startDrag(_ item: Any) {
    guard let item = item as? Item else { return }
    resetDragState()
    active = item
    draggedItems = itemsBeingDragged(startingWith: item)
    AppState.shared.navigator.isDragAndDropInProgress = true
  }

  private func resetDragState() {
    draggedItems = []
    active = nil
    lastDropPosition = nil
    AppState.shared.navigator.isDragAndDropInProgress = false
  }

  private func itemsBeingDragged(startingWith item: Item) -> [Item] {
    selection.items.contains(item)
      ? items.filter { selection.items.contains($0) }
      : [item]
  }

  private func move(to item: Any, at edge: ReorderableDropEdge) {
    guard let item = item as? Item else { return }
    guard !draggedItems.contains(item), let current = active else { return }
    let dropPosition = DropPosition(itemID: item.id, edge: edge)
    guard dropPosition != lastDropPosition else { return }
    lastDropPosition = dropPosition

    guard let currentIndex = items.firstIndex(of: current) else { return }
    guard let targetIndex = items.firstIndex(of: item) else { return }
    guard let destinationIndex = reorderDestination(
      currentIndex: currentIndex,
      targetIndex: targetIndex,
      edge: edge
    ) else { return }

    let source = sourceIndexes
    guard !source.isEmpty else { return }
    moveAction(source, destinationIndex)
  }

  private var sourceIndexes: IndexSet {
    var source = IndexSet()
    for (index, item) in items.enumerated() where draggedItems.contains(item) {
      source.insert(index)
    }
    return source
  }
}

private struct DropPosition<ItemID: Hashable>: Equatable {
  let itemID: ItemID
  let edge: ReorderableDropEdge
}

@available(macOS 26.0, *)
private struct DraggableItemModifier<Item: Reorderable>: ViewModifier {
  @Environment(\.reorderableDragContext) private var dragContext

  let item: Item

  @ViewBuilder
  func body(content: Content) -> some View {
    if let dragContext {
      content
        .opacity(dragContext.isDragged(item) ? 0.5 : 1)
        .onDrag {
          dragContext.startDrag(item)
          return itemProvider(for: item, contentType: dragContext.contentType)
        } preview: {
          dragContext.dragPreview(item)
        }
        .dragConfiguration(
          DragConfiguration(
            operationsWithinApp: .init(allowCopy: false, allowMove: true),
            operationsOutsideApp: .init(allowCopy: false, allowMove: false)
          )
        )
        .onDragSessionUpdated { session in
          switch session.phase {
          case .ended:
            dragContext.resetDragState()
          default:
            break
          }
        }
        .onDrop(of: [dragContext.contentType], isTargeted: nil) { _ in
          dragContext.resetDragState()
          return true
        }
        .onDropSessionUpdated { session in
          switch session.phase {
          case .entering, .active:
            dragContext.move(
              item,
              dropEdge(at: session.location, in: session.size)
            )
          case .ended:
            dragContext.resetDragState()
          default:
            break
          }
        }
    } else {
      content
    }
  }

}

private func itemProvider<Item: Reorderable>(
  for item: Item,
  contentType: UTType
) -> NSItemProvider {
  let provider = NSItemProvider()
  provider.registerDataRepresentation(
    forTypeIdentifier: contentType.identifier,
    visibility: .ownProcess
  ) { completion in
    completion(String(describing: item.id).data(using: .utf8), nil)
    return nil
  }
  return provider
}

struct ReorderableDragContext {
  let contentType: UTType
  let isDragged: (Any) -> Bool
  let dragPreview: (Any) -> AnyView
  let startDrag: (Any) -> Void
  let resetDragState: () -> Void
  let move: (Any, ReorderableDropEdge) -> Void
}

enum ReorderableDropEdge: Equatable {
  case before
  case after
}

func dropEdge(at location: CGPoint, in targetSize: CGSize) -> ReorderableDropEdge {
  location.y < targetSize.height / 2 ? .before : .after
}

func reorderDestination(
  currentIndex: Int,
  targetIndex: Int,
  edge: ReorderableDropEdge
) -> Int? {
  if currentIndex < targetIndex {
    // Move destinations use indexes from before the source is removed, so a
    // downward move needs to insert after the target.
    return edge == .after ? targetIndex + 1 : nil
  }
  if currentIndex > targetIndex {
    return edge == .before ? targetIndex : nil
  }
  return nil
}

private struct ReorderableDragContextKey: EnvironmentKey {
  static let defaultValue: ReorderableDragContext? = nil
}

extension EnvironmentValues {
  var reorderableDragContext: ReorderableDragContext? {
    get { self[ReorderableDragContextKey.self] }
    set { self[ReorderableDragContextKey.self] = newValue }
  }
}

extension View {
  @ViewBuilder
  func draggableContainer<Item: Reorderable, DragPreview: View>(
    items: [Item],
    contentType: UTType,
    @ViewBuilder dragPreview: @escaping ([Item]) -> DragPreview,
    selection: Binding<Selection<Item>>,
    draggedItems: Binding<[Item]>,
    moveAction: @escaping (IndexSet, Int) -> Void
  ) -> some View where Item.ID: Sendable {
    if #available(macOS 27.0, *) {
      modifier(
        NativeDraggableContainerModifier(
          items: items,
          selection: selection,
          draggedItems: draggedItems,
          moveAction: moveAction
        )
      )
    } else {
      modifier(
        DraggableContainerModifier(
          items: items,
          contentType: contentType,
          dragPreview: dragPreview,
          selection: selection,
          draggedItems: draggedItems,
          moveAction: moveAction
        )
      )
    }
  }

  @ViewBuilder
  func draggableItem<Item: Reorderable>(_ item: Item) -> some View {
    // macOS 27 natively supports reorderable containers.
    // macOS 26 adds onDragSessionUpdated as an API which makes detecting when a drag session
    // has ended much more reliable and smoother. The legacy implementation is to bridge that
    // gap but should be removed in the future.
    if #available(macOS 27.0, *) {
      // The enclosing ForEach supplies native drag sources through reorderable().
      self
    } else if #available(macOS 26.0, *) {
      modifier(DraggableItemModifier(item: item))
    } else {
      modifier(LegacyDraggableItemModifier(item: item))
    }
  }
}

extension DynamicViewContent {
  @ViewBuilder
  func reorderableItems() -> some View {
    if #available(macOS 27.0, *) {
      reorderable()
    } else {
      self
    }
  }
}
