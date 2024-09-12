import Foundation
import SwiftData

@MainActor
class Storage {
  static let shared = Storage()

  var container: ModelContainer
  var context: ModelContext { container.mainContext }

  private let url = URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite")

  init() {
    var config = ModelConfiguration(url: url)

    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") {
      config = ModelConfiguration(isStoredInMemoryOnly: true)
    }
    #endif

    do {
      container = try ModelContainer(for: HistoryItem.self, configurations: config)
    } catch let error {
      fatalError("Cannot load database: \(error.localizedDescription).")
    }
  }
}
