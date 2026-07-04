import AppKit

// Memory-governance scaffolding: reclaims transient images on memory warning.
// `MemoryGovernor` drops non-visible decorators' transient bitmaps and purges
// the app-icon cache. Per-item decoded bitmaps stay bounded to the visible
// window via per-decorator `previewImage` (released on scroll-out) plus the
// preview-size cap; a separate shared decoded-image cache was intentionally
// removed — preview bitmaps are not the memory lever, and a retained shared
// cache (countLimit=32) would increase memory for only marginal re-show value.

/// Why transient images are being released; drives how much each call drops.
enum ReleaseReason {
  case scrollOut
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
  /// app-icon cache. The remaining spec'd flush targets — the thumbnail memory
  /// tier and the regexp cache — are `NSCache`-backed and auto-evict on system
  /// memory pressure, so an explicit purge here is redundant.
  func handleMemoryWarning() {
    let visibleIDs = VisibilityTracker.shared.snapshot()
    for decorator in history?.decorators() ?? [] where !visibleIDs.contains(decorator.id) {
      decorator.releaseTransientImages(.memoryWarning)
    }
    ApplicationImageCache.shared.purge()
  }
}
