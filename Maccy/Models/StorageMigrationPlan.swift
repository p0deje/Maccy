import Foundation
import SwiftData

enum StorageSchemaV1: VersionedSchema {
  static var versionIdentifier = Schema.Version(1, 0, 0)
  static var models: [any PersistentModel.Type] {
    [HistoryItem.self, HistoryItemContent.self]
  }

  @Model class HistoryItem {
    var application: String?
    var firstCopiedAt: Date = Date.now
    var lastCopiedAt: Date = Date.now
    var numberOfCopies: Int = 1
    var pin: String?
    var title = ""

    @Relationship(deleteRule: .cascade, inverse: \HistoryItemContent.item)
    var contents: [HistoryItemContent] = []

    init() {}
  }

  @Model class HistoryItemContent {
    var type: String = ""
    var value: Data?

    @Relationship
    var item: HistoryItem?

    init() {}
  }
}

enum StorageSchemaV2: VersionedSchema {
  static var versionIdentifier = Schema.Version(2, 0, 0)
  static var models: [any PersistentModel.Type] {
    [HistoryItem.self, HistoryItemContent.self]
  }
}

enum StorageMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] {
    [StorageSchemaV1.self, StorageSchemaV2.self]
  }

  static var stages: [MigrationStage] {
    [migrateV1toV2]
  }

  static let migrateV1toV2 = MigrationStage.custom(
    fromVersion: StorageSchemaV1.self,
    toVersion: StorageSchemaV2.self,
    willMigrate: nil,
    didMigrate: { context in
      let items = try context.fetch(FetchDescriptor<HistoryItem>())
      for item in items {
        item.tags = []
      }
      try context.save()
    }
  )
}
