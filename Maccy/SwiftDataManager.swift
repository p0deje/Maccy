import Foundation
import SwiftData

class SwiftDataManager {
  static let shared = SwiftDataManager()

  @MainActor
  var container: ModelContainer

  init() {
    let config = ModelConfiguration(url: URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite"))
    container = try! ModelContainer(for: HistoryItem.self, configurations: config)
  }
}
