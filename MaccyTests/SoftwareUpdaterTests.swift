import Testing
@testable import Maccy

@MainActor
struct SoftwareUpdaterTests {
  @Test("Updater is started at launch, not when Settings opens")
  func startedAtLaunch() throws {
    let updater = try #require(AppState.shared.appDelegate?.updater)
    #expect(updater === SoftwareUpdater.shared)
    #expect(updater.canCheckForUpdates)
  }
}
