import Sparkle

class SoftwareUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
  @Published
  var automaticallyChecksForUpdates = false {
    didSet {
      updater?.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }
  }

  private var updater: SPUUpdater?
  private var automaticallyChecksForUpdatesObservation: NSKeyValueObservation?

  override init() {
    super.init()

    updater = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: self,
      userDriverDelegate: nil
    ).updater

    automaticallyChecksForUpdatesObservation = updater?.observe(
      \.automaticallyChecksForUpdates,
      options: [.initial, .new, .old],
      changeHandler: { [unowned self] updater, change in
        guard change.newValue != change.oldValue else { return }
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
      }
    )
  }

  func checkForUpdates() {
    updater?.checkForUpdates()
  }
}
