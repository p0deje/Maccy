import AppKit

// C1 (master plan, bs6.1-bs6.3): memory-governance scaffolding — pure additions
// wired in C2/C3. Bounds the decoded-image working set to the visible window and
// reclaims it on memory warning. See 14-master-plan.md.

/// Why transient images are being released; drives how much each call drops.
enum ReleaseReason {
  case scrollOut
  case previewHidden
  case settingChange
  case memoryWarning
  case invalidate
}

/// Read-only handle to a history's decorators for memory-pressure iteration.
/// `History` conforms; decouples `MemoryGovernor` from `History`.
protocol HistoryRef: AnyObject {
  func decorators() -> [HistoryItemDecorator]
}

/// Reports viewport transitions. `HistoryItemDecorator` conforms; the
/// `VisibilityTracker` is driven from the list's `.onAppear`/`.onDisappear`.
protocol VisibilityObserving: AnyObject {
  var id: UUID { get }
  func onAppearInViewport()
  func onDisappearFromViewport()
}

/// Tracks which decorators are currently in the viewport (main-actor).
@MainActor
final class VisibilityTracker {
  static let shared = VisibilityTracker()
  private var visible: Set<UUID> = []

  func register(_ observer: VisibilityObserving) {
    visible.insert(observer.id)
  }

  func unregister(_ observer: VisibilityObserving) {
    visible.remove(observer.id)
  }

  func isVisible(_ id: UUID) -> Bool {
    visible.contains(id)
  }

  /// IDs currently in the viewport; `MemoryGovernor` reclaims the complement.
  func snapshot() -> Set<UUID> {
    visible
  }
}

/// Bounded cache of decoded preview bitmaps keyed by item id. Lets decoded
/// bitmaps be shared/evicted by cost instead of retained per decorator.
final class DecodedImageCache: @unchecked Sendable {
  static let shared = DecodedImageCache()
  private let cache: NSCache<NSUUID, NSImage> = {
    let cache = NSCache<NSUUID, NSImage>()
    cache.countLimit = 32
    cache.totalCostLimit = 64 * 1024 * 1024
    return cache
  }()

  func image(for id: UUID) -> NSImage? {
    cache.object(forKey: id as NSUUID)
  }

  func setImage(_ image: NSImage, for id: UUID, cost: Int) {
    cache.setObject(image, forKey: id as NSUUID, cost: cost)
  }

  func evict(_ id: UUID) {
    cache.removeObject(forKey: id as NSUUID)
  }

  func purgeAll() {
    cache.removeAllObjects()
  }
}

/// Coordinates reclamation on memory warning. Attached to `History` at launch so
/// it can iterate non-visible decorators. `@MainActor` — the state it touches is
/// main-isolated.
@MainActor
final class MemoryGovernor {
  static let shared = MemoryGovernor()
  private weak var history: HistoryRef?
  private var observer: NSObjectProtocol?

  func attach(history: HistoryRef) {
    self.history = history
  }

  func start() {
    guard observer == nil else { return }
    // Route through the singleton: the observer closure is @Sendable and
    // MemoryGovernor isn't Sendable.
    observer = NotificationCenter.default.addObserver(
      forName: NSApplication.didReceiveMemoryWarningNotification,
      object: nil,
      queue: .main
    ) { _ in
      MemoryGovernor.shared.handleMemoryWarning()
    }
  }

  func stop() {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
      self.observer = nil
    }
  }

  /// Drop transient images for every decorator NOT in the viewport, plus the
  /// shared decoded-image cache and app-icon cache.
  func handleMemoryWarning() {
    let visibleIDs = VisibilityTracker.shared.snapshot()
    for decorator in history?.decorators() ?? [] where !visibleIDs.contains(decorator.id) {
      decorator.releaseTransientImages(.memoryWarning)
    }
    DecodedImageCache.shared.purgeAll()
    ApplicationImageCache.shared.purge()
  }
}
