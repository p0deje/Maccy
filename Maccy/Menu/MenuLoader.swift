import AppKit

// Dummy menu for NSStatusItem which allows to asynchronously
// execute callback when it's being opened. This gives us an
// possibility to load other menu in a non-blocking manner.
// See Maccy.withFocus() for more details about why this is needed.
class MenuLoader: NSMenu, NSMenuDelegate {
  typealias LoaderCallback = (NSEvent?) -> Void
  private var loader: LoaderCallback!

  required init(coder decoder: NSCoder) {
    super.init(coder: decoder)
  }

  init(_ loader: @escaping LoaderCallback) {
    super.init(title: "Loader")
    addItem(withTitle: "Loading…", action: nil, keyEquivalent: "")
    self.delegate = self
    self.loader = loader
  }

  func menuWillOpen(_ menu: NSMenu) {
    let event = NSApp.currentEvent
    menu.cancelTrackingWithoutAnimation()
    // Just calling loader() doesn't work when avoidTakingFocus is true.
    Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { _ in
      self.loader(event)
    }
  }
}
