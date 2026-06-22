import Foundation

struct SnippetSearchResult: Equatable {
  var folder: SnippetFolder
  var snippet: Snippet
  var ranges: [Range<String.Index>]

  var title: String {
    SnippetSearch.title(folder: folder, snippet: snippet)
  }
}

final class SnippetSearch {
  static func title(folder: SnippetFolder, snippet: Snippet) -> String {
    "\(folder.name) / \(snippet.name)"
  }

  func search(_ query: String, in folders: [SnippetFolder]) -> [SnippetSearchResult] {
    let tokens = query
      .split(whereSeparator: \.isWhitespace)
      .map(String.init)

    guard !tokens.isEmpty else {
      return []
    }

    return folders.flatMap { folder in
      folder.snippets.compactMap { snippet in
        guard matches(tokens: tokens, folder: folder, snippet: snippet) else {
          return nil
        }

        let title = Self.title(folder: folder, snippet: snippet)
        return SnippetSearchResult(
          folder: folder,
          snippet: snippet,
          ranges: highlightRanges(for: tokens, in: title)
        )
      }
    }
  }

  private func matches(tokens: [String], folder: SnippetFolder, snippet: Snippet) -> Bool {
    tokens.allSatisfy { token in
      matchesMetadata(token, folder: folder, snippet: snippet) ||
        matchesContent(token, snippet: snippet)
    }
  }

  private func matchesMetadata(_ token: String, folder: SnippetFolder, snippet: Snippet) -> Bool {
    [
      folder.name,
      snippet.name
    ].contains { value in
      value.range(of: token, options: .caseInsensitive) != nil
    }
  }

  private func matchesContent(_ token: String, snippet: Snippet) -> Bool {
    // 内容搜索太容易误命中，至少输入两个字符才参与匹配。
    guard token.count >= 2 else {
      return false
    }

    return snippet.content.range(of: token, options: .caseInsensitive) != nil
  }

  private func highlightRanges(for tokens: [String], in title: String) -> [Range<String.Index>] {
    tokens.compactMap { token in
      title.range(of: token, options: .caseInsensitive)
    }
  }
}
