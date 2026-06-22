import Foundation

struct Snippet: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var name: String
  var content: String

  init(id: UUID = UUID(), name: String, content: String = "") {
    self.id = id
    self.name = name
    self.content = content
  }
}

struct SnippetFolder: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var name: String
  var icon: String?
  var snippets: [Snippet]

  init(id: UUID = UUID(), name: String, icon: String? = nil, snippets: [Snippet] = []) {
    self.id = id
    self.name = name
    self.icon = icon
    self.snippets = snippets
  }
}

enum SnippetFolderIcon {
  static let presets = [
    "🚀", "💡", "⭐️", "✅", "📌", "📝",
    "📎", "🔖", "🔗", "📣", "🎯", "⚡️",
    "🧠", "🧰", "🛠️", "💬", "✉️", "📁"
  ]
}
