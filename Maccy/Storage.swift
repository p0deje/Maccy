import Defaults
import Foundation
import SwiftData

@MainActor
class Storage {
  static let shared = Storage()

  var container: ModelContainer
  var context: ModelContext { container.mainContext }
  var size: String {
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).allValues.first?.value as? Int64, size > 1 else {
      return ""
    }

    return ByteCountFormatter().string(fromByteCount: size)
  }

  private let url = URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite")

  init() {
    var config = ModelConfiguration(url: url)

    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") {
      config = ModelConfiguration(isStoredInMemoryOnly: true)
    }
    #endif

    do {
      container = try ModelContainer(
        for: HistoryItem.self, Workspace.self,
        configurations: config
      )
    } catch let error {
      fatalError("Cannot load database: \(error.localizedDescription).")
    }
  }

  /// Ensures a "Default" workspace exists and migrates any orphaned history items into it.
  func ensureDefaultWorkspace() {
    let defaultName = Workspace.defaultName
    let descriptor = FetchDescriptor<Workspace>(
      predicate: #Predicate { $0.name == defaultName }
    )

    let defaultWorkspace: Workspace
    if let existing = try? context.fetch(descriptor).first {
      defaultWorkspace = existing
    } else {
      defaultWorkspace = Workspace(name: Workspace.defaultName)
      context.insert(defaultWorkspace)
    }

    // Migrate orphaned items (workspace == nil) to the default workspace.
    let orphanDescriptor = FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.workspace == nil }
    )
    if let orphans = try? context.fetch(orphanDescriptor) {
      for item in orphans {
        item.workspace = defaultWorkspace
      }
    }

    context.processPendingChanges()
    try? context.save()

    // Persist the active workspace ID if not already set.
    if Defaults[.activeWorkspaceId] == nil {
      Defaults[.activeWorkspaceId] = defaultWorkspace.id.uuidString
    }
  }
}
