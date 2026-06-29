import AppIntents

/// App Intents entity exposing a clipboard item's contents to Shortcuts and friends.
struct HistoryItemAppEntity: TransientAppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Clipboard item")

  /// File URL referenced by the item, if any.
  @Property(title: "File")
  var file: URL?

  /// HTML source of the item, if any.
  @Property(title: "HTML")
  var html: String?

  /// URL of the temporary PNG written for the item's image, if any.
  @Property(title: "Image")
  var image: URL?

  /// RTF-decoded rich text of the item, if any.
  @Property(title: "Rich Text")
  var richText: String?

  /// Plain text of the item, if any.
  @Property(title: "Text")
  var text: String?

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "Clipboard item")
  }
}
