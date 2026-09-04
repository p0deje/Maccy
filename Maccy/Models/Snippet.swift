import Foundation
import SwiftData

@Model
class SnippetFolder {
  @Attribute(.unique) var id: UUID
  var name: String
  var order: Int
  @Relationship(deleteRule: .cascade, inverse: \Snippet.folder) var snippets: [Snippet]

  init(name: String, order: Int = 0) {
    id = UUID()
    self.name = name
    self.order = order
    snippets = []
  }
}

@Model
class Snippet {
  @Attribute(.unique) var id: UUID
  var name: String
  var content: String
  var order: Int
  var folder: SnippetFolder?

  init(name: String, content: String = "", order: Int = 0, folder: SnippetFolder? = nil) {
    id = UUID()
    self.name = name
    self.content = content
    self.order = order
    self.folder = folder
  }
}
