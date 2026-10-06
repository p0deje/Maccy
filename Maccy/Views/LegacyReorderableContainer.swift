import AppKit
import SwiftUI
import UniformTypeIdentifiers

internal struct LegacyDraggableItemModifier<Item: Reorderable>: ViewModifier {
  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags
  @Environment(\.reorderableDragContext) private var dragContext
  @State private var dropTargetSize: CGSize = .zero

  let item: Item

  @ViewBuilder
  func body(content: Content) -> some View {
    if let dragContext {
      content
        .opacity(dragContext.isDragged(item) ? 0.5 : 1)
        .onGeometryChange(for: CGSize.self) { proxy in
          proxy.size
        } action: { size in
          dropTargetSize = size
        }
        .background(
          LegacyDragSourceView(
            item: item,
            dragContext: dragContext,
            appState: appState,
            modifierFlags: modifierFlags
          )
        )
        .onDrop(
          of: [dragContext.contentType],
          delegate: LegacyDraggableItemDropDelegate(
            item: item,
            dragContext: dragContext,
            targetSize: dropTargetSize
          )
        )
    } else {
      content
    }
  }
}

private struct LegacyDraggableItemDropDelegate<Item: Reorderable>: DropDelegate {
  let item: Item
  let dragContext: ReorderableDragContext
  let targetSize: CGSize

  func validateDrop(info: DropInfo) -> Bool {
    info.hasItemsConforming(to: [dragContext.contentType])
  }

  func dropEntered(info: DropInfo) {
    move(info)
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    move(info)
    return DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    dragContext.resetDragState()
    return true
  }

  private func move(_ info: DropInfo) {
    guard targetSize.height > 0 else { return }
    dragContext.move(item, dropEdge(at: info.location, in: targetSize))
  }
}

private struct LegacyDragSourceView<Item: Reorderable>: NSViewRepresentable {
  let item: Item
  let dragContext: ReorderableDragContext
  let appState: AppState
  let modifierFlags: ModifierFlags

  func makeNSView(context: Context) -> DragSourceView {
    let view = DragSourceView()
    view.configuration = configuration
    return view
  }

  func updateNSView(_ view: DragSourceView, context: Context) {
    view.configuration = configuration
  }

  static func dismantleNSView(_ view: DragSourceView, coordinator: ()) {
    view.removeEventMonitor()
  }

  private var configuration: LegacyDragSourceConfiguration {
    LegacyDragSourceConfiguration(
      contentType: dragContext.contentType,
      makeDragPreview: { sourceView in
        dragPreviewImage(
          for: dragContext.dragPreview(item),
          sourceView: sourceView,
          appState: appState,
          modifierFlags: modifierFlags
        )
      },
      onDragStarted: {
        dragContext.startDrag(item)
      },
      onDragEnded: {
        dragContext.resetDragState()
      }
    )
  }
}

private struct LegacyDragSourceConfiguration {
  let contentType: UTType
  let makeDragPreview: (NSView) -> NSImage
  let onDragStarted: () -> Void
  let onDragEnded: () -> Void
}

private final class DragSourceView: NSView, NSDraggingSource {
  var configuration: LegacyDragSourceConfiguration? {
    didSet {
      updateEventMonitor()
    }
  }

  private var localEventMonitor: Any?
  private var mouseDownEvent: NSEvent?
  private var isDragging = false

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateEventMonitor()
  }

  override var isFlipped: Bool {
    true
  }

  func updateEventMonitor() {
    if window != nil, configuration != nil, localEventMonitor == nil {
      localEventMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
      ) { [weak self] event in
        self?.handle(event) ?? event
      }
    } else if window == nil || configuration == nil {
      removeEventMonitor()
    }
  }

  func removeEventMonitor() {
    if let localEventMonitor {
      NSEvent.removeMonitor(localEventMonitor)
      self.localEventMonitor = nil
    }
    mouseDownEvent = nil
    isDragging = false
  }

  deinit {
    removeEventMonitor()
  }

  private func handle(_ event: NSEvent) -> NSEvent? {
    switch event.type {
    case .leftMouseDown:
      mouseDownEvent = contains(event) ? event : nil
      return event
    case .leftMouseDragged:
      guard mouseDownEvent != nil, !isDragging else { return event }
      startDragging(with: event)
      return nil
    case .leftMouseUp:
      mouseDownEvent = nil
      return event
    default:
      return event
    }
  }

  private func contains(_ event: NSEvent) -> Bool {
    guard event.window == window else { return false }
    return bounds.contains(convert(event.locationInWindow, from: nil))
  }

  private func startDragging(with event: NSEvent) {
    guard let configuration else { return }

    isDragging = true
    configuration.onDragStarted()

    let pasteboardItem = NSPasteboardItem()
    pasteboardItem.setString(
      UUID().uuidString,
      forType: NSPasteboard.PasteboardType(configuration.contentType.identifier)
    )

    let preview = configuration.makeDragPreview(self)
    let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
    draggingItem.setDraggingFrame(
      NSRect(origin: .zero, size: preview.size),
      contents: preview
    )

    beginDraggingSession(with: [draggingItem], event: event, source: self)
  }

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    context == .withinApplication ? .move : []
  }

  func draggingSession(
    _ session: NSDraggingSession,
    endedAt screenPoint: NSPoint,
    operation: NSDragOperation
  ) {
    isDragging = false
    mouseDownEvent = nil
    configuration?.onDragEnded()
  }
}

private func dragPreviewImage(
  for preview: AnyView,
  sourceView: NSView,
  appState: AppState,
  modifierFlags: ModifierFlags
) -> NSImage {
  let hostingView = NSHostingView(
    rootView:
      preview
      .environment(appState)
      .environment(modifierFlags)
  )
  let fittingSize = hostingView.fittingSize
  let size = NSSize(
    width: max(sourceView.bounds.width, 1),
    height: max(sourceView.bounds.height, fittingSize.height, 1)
  )

  hostingView.frame = NSRect(origin: .zero, size: size)
  hostingView.layoutSubtreeIfNeeded()

  guard
    let bitmap = hostingView.bitmapImageRepForCachingDisplay(
      in: hostingView.bounds
    )
  else {
    return NSImage(size: size)
  }
  hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

  let image = NSImage(size: size)
  image.addRepresentation(bitmap)
  return image
}
