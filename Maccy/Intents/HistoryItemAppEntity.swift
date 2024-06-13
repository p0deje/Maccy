import AppIntents

struct HistoryItemAppEntity: TransientAppEntity {
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Clipboard item")

  @Property(title: "File")
  var file: IntentFile?

  @Property(title: "HTML")
  var html: String?

  @Property(title: "Image")
  var image: IntentFile?

  @Property(title: "Rich Text")
  var richText: String?

  @Property(title: "Text")
  var text: String?

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "Clipboard item")
  }
}
