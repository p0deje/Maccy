import AppKit

// Memory-governance scaffolding: bounds the decoded-image working set to the
// visible window and reclaims it on memory warning. Status: partially wired —
// `MemoryGovernor` reclamation and `DecodedImageCache.evict`/`purgeAll` are
// called, but `DecodedImageCache.setImage`/`image(for:)` have zero callers (the
// read path was never connected), so the decode-cache tier is effectively dead.

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
@MainActor
protocol HistoryRef: AnyObject {
  /// All decorators (visible or not).
  func decorators() -> [HistoryItemDecorator]
}

/// Provides the identity `VisibilityTracker` keys on. The viewport
/// appear/disappear handlers are concrete `@MainActor` methods on the conformer
/// (not protocol requirements) so they can call main-isolated work without
/// pulling the whole conforming type to `@MainActor` (a `@MainActor` protocol
/// would infer the conformer's isolation and break its non-isolated members).
protocol VisibilityObserving: AnyObject {
  var id: UUID { get }
}

/// Tracks which decorators are currently in the viewport (main-actor).
@MainActor
final class VisibilityTracker {
  static let shared = VisibilityTracker()
  private var visible: Set<UUID> = []

  /// Records `observer` as currently visible.
  func register(_ observer: VisibilityObserving) {
    visible.insert(observer.id)
  }

  /// Removes `observer` from the visible set.
  func unregister(_ observer: VisibilityObserving) {
    visible.remove(observer.id)
  }

  /// Whether `id` is currently visible.
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
@MainActor
final class DecodedImageCache {
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

  /// Removes the cached image for `id` (if any).
  func evict(_ id: UUID) {
    cache.removeObject(forKey: id as NSUUID)
  }

  /// Empties the whole cache.
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
  private var memoryPressureSource: DispatchSourceMemoryPressure?

  /// Binds the governor to a history it can iterate on memory warning.
  func attach(history: HistoryRef) {
    self.history = history
  }

  /// Starts listening for system memory-pressure events (no-op if already started).
  func start() {
    guard memoryPressureSource == nil else { return }
    // macOS has no `NSApplication.didReceiveMemoryWarningNotification` (that's
    // iOS `UIApplication`); use the dispatch memory-pressure source, signalled
    // at `.warning`/`.critical`. The handler runs on `.main` but is `@Sendable`,
    // so hop via `assumeIsolated` (`MemoryGovernor` isn't `Sendable`).
    let source = DispatchSource.makeMemoryPressureSource(
      eventMask: [.warning, .critical],
      queue: .main
    )
    source.setEventHandler {
      MainActor.assumeIsolated { MemoryGovernor.shared.handleMemoryWarning() }
    }
    source.resume()
    memoryPressureSource = source
  }

  /// Stops listening for memory-pressure events.
  func stop() {
    memoryPressureSource?.cancel()
    memoryPressureSource = nil
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
