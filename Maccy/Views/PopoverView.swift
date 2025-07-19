import SwiftUI

struct PopoverView<Value, T: View>: NSViewRepresentable {
  @Binding private var item: Value?
  private let content: (Value?) -> T
  private var lastItem: Value? = nil

  init(item: Binding<Value?>, @ViewBuilder content: @escaping (Value?) -> T) {
    self._item = item
    self.content = content
  }

  func makeNSView(context: Context) -> NSView {
    return .init()
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    let coordinator = context.coordinator
    let currentItem = item
    coordinator.popover.contentViewController = NSHostingController(rootView: content(currentItem ?? coordinator.lastItem))
    coordinator.lastItem = currentItem
    coordinator.visibilityDidChange(currentItem != nil, in: nsView)
  }

  func makeCoordinator() -> Coordinator {
    let coordinator = Coordinator(popover: .init())
    coordinator.popover.contentViewController = NSHostingController(rootView: content(nil))
    return coordinator
  }

  @MainActor
  final class Coordinator: NSObject, NSPopoverDelegate {
    fileprivate let popover: NSPopover
    fileprivate var lastItem: Value? = nil
    var oldFrame: NSRect = .zero


    fileprivate init(popover: NSPopover) {
      self.popover = popover
      super.init()
      popover.delegate = self

      // Prevent NSPopover from becoming first responder.
      popover.behavior = .semitransient
    }

    fileprivate func visibilityDidChange(_ isVisible: Bool, in view: NSView) {
      if isVisible {
        if oldFrame == .zero {
          oldFrame = view.frame
        } else {
          view.frame = oldFrame
        }

        popover.show(relativeTo: .zero, of: view, preferredEdge: .maxX)
        // Ugly hack to hide the anchor arrow
        view.frame = NSMakeRect(-1000, 0, 10, 10)

      } else if popover.isShown {
        popover.close()
      }
    }
  }
}
