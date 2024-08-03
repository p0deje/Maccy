import AppIntents

struct HistoryItemAppEntity: TransientAppEntity {
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Clipboard item")

  @Property(title: "File")
  var file: URL?

  @Property(title: "HTML")
  var html: String?

  @Property(title: "Image")
  var image: URL?

  @Property(title: "Rich Text")
  var richText: String?

  @Property(title: "Text")
  var text: String?

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "Clipboard item")
  }
}
