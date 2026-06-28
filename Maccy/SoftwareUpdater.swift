import Sparkle

@MainActor
@Observable
class SoftwareUpdater {
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
      // SPUUpdater is main-affine). Re-enter @MainActor via a synchronous
      // assertion (no async hop) so the @Sendable closure can mutate self
      // without capturing a non-Sendable self across actors.
      let newValue = updater.automaticallyChecksForUpdates
      MainActor.assumeIsolated {
        self?.automaticallyChecksForUpdates = newValue
      }
    }
  }

  func checkForUpdates() {
    updater.checkForUpdates()
  }
}
