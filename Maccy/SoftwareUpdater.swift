import Sparkle

/// Wraps Sparkle's `SPUUpdater` to drive and reflect automatic update checks.
@MainActor
@Observable
class SoftwareUpdater {
  /// Whether Maccy should check for updates automatically; mirrored to the
  /// underlying `SPUUpdater` and kept in sync with its KVO notifications.
  var automaticallyChecksForUpdates = false {
    didSet {
      updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }
  }

  private var updater: SPUUpdater
  private var automaticallyChecksForUpdatesObservation: NSKeyValueObservation?

  private let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )

  /// Initializes the updater and observes `SPUUpdater.automaticallyChecksForUpdates`
  /// so external changes (e.g. from System settings) propagate into the binding.
  init() {
    updater = updaterController.updater
    automaticallyChecksForUpdatesObservation = updater.observe(
      \.automaticallyChecksForUpdates,
      options: [.initial, .new, .old]
    ) { [weak self] updater, change in
      guard change.newValue != change.oldValue else {
        return
      }

      // KVO fires on the registering thread (main, since init runs on main and
      // SPUUpdater is main-affine). Re-enter the main actor via a synchronous
      // assertion (no async hop) so the @Sendable closure can mutate `self`
      // without capturing a non-Sendable `self` across actors.
      let newValue = updater.automaticallyChecksForUpdates
      MainActor.assumeIsolated {
        self?.automaticallyChecksForUpdates = newValue
      }
    }
  }

  /// Prompts Sparkle to check for updates immediately.
  func checkForUpdates() {
    updater.checkForUpdates()
  }
}
