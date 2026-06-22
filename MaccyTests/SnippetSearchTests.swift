import XCTest
@testable import Maccy

final class SnippetSearchTests: XCTestCase {
  func testSnippetEmojiAccessoryUsesTextRendering() throws {
    let item = HistoryItem()
    let decorator = HistoryItemDecorator(item, source: .snippet(UUID()), snippetFolderIcon: "✅")

    XCTAssertEqual(decorator.snippetAccessoryText, "✅")
    XCTAssertNil(decorator.snippetAccessoryImage)
  }

  func testFolderIconPresetsContainCommonChoices() {
    XCTAssertTrue(SnippetFolderIcon.presets.contains("🚀"))
    XCTAssertTrue(SnippetFolderIcon.presets.contains("💡"))
    XCTAssertEqual(Set(SnippetFolderIcon.presets).count, SnippetFolderIcon.presets.count)
  }

  func testEmptyQueryHidesSnippets() {
    let snippets = [
      SnippetFolder(name: "aaa", snippets: [
        Snippet(name: "bbb", content: "cdef")
      ])
    ]

    XCTAssertEqual(SnippetSearch().search("", in: snippets), [])
  }

  func testFolderAndSnippetNameMustBothBeSearchable() {
    let folder = SnippetFolder(name: "aaa", snippets: [
      Snippet(name: "bbb", content: "cdef")
    ])

    XCTAssertEqual(SnippetSearch().search("aaa bbb", in: [folder]).map(\.snippet.name), ["bbb"])
  }

  func testContentMatchesWhenQueryHasAtLeastTwoCharacters() {
    let folder = SnippetFolder(name: "aaa", snippets: [
      Snippet(name: "bbb", content: "cdef")
    ])

    XCTAssertEqual(SnippetSearch().search("cd", in: [folder]).map(\.snippet.name), ["bbb"])
  }

  func testContentDoesNotMatchSingleCharacterQuery() {
    let folder = SnippetFolder(name: "aaa", snippets: [
      Snippet(name: "bbb", content: "cdef")
    ])

    XCTAssertEqual(SnippetSearch().search("c", in: [folder]), [])
  }

  func testKeywordsFromLegacyDataAreNotSearchable() throws {
    let data = """
    [
      {
        "id": "11111111-1111-1111-1111-111111111111",
        "name": "general",
        "snippets": [
          {
            "id": "22222222-2222-2222-2222-222222222222",
            "name": "reply",
            "content": "Thanks",
            "keywords": "email template"
          }
        ]
      }
    ]
    """.data(using: .utf8)!
    let folders = try JSONDecoder().decode([SnippetFolder].self, from: data)

    XCTAssertEqual(SnippetSearch().search("email", in: folders), [])
  }

  func testStorePersistsNestedSnippetEdits() throws {
    let suiteName = "org.p0deje.Maccy.SnippetStoreTests.\(UUID().uuidString)"
    let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }

    let store = SnippetsStore(userDefaults: userDefaults)
    let folderID = store.addFolder(name: "aaa")
    let snippetID = try XCTUnwrap(store.addSnippet(to: folderID))
    store.updateSnippet(
      id: snippetID,
      in: folderID,
      name: "bbb",
      content: "cdef"
    )

    let reloadedStore = SnippetsStore(userDefaults: userDefaults)
    XCTAssertEqual(reloadedStore.folders, [
      SnippetFolder(
        id: folderID,
        name: "aaa",
        snippets: [
          Snippet(id: snippetID, name: "bbb", content: "cdef")
        ]
      )
    ])
  }

  func testStorePersistsFolderIcon() {
    let suiteName = "org.p0deje.Maccy.SnippetStoreTests.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }

    let store = SnippetsStore(userDefaults: userDefaults)
    let folderID = store.addFolder(name: "aaa")
    store.updateFolderIcon(id: folderID, to: "🚀")

    let reloadedStore = SnippetsStore(userDefaults: userDefaults)
    XCTAssertEqual(reloadedStore.folder(id: folderID)?.icon, "🚀")
  }

  func testStoreSearchResultsUseFolderAndSnippetTitle() {
    let suiteName = "org.p0deje.Maccy.SnippetStoreTests.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }

    let store = SnippetsStore(userDefaults: userDefaults)
    let folderID = store.addFolder(name: "aaa")
    let snippetID = store.addSnippet(to: folderID)
    store.updateSnippet(id: snippetID, in: folderID, name: "bbb", content: "cdef")

    XCTAssertEqual(store.searchResults(for: "aaa bbb").map(\.object.title), ["aaa / bbb"])
  }

  func testStoreSearchResultsUseFolderIconForSnippetRows() throws {
    let suiteName = "org.p0deje.Maccy.SnippetStoreTests.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }

    let store = SnippetsStore(userDefaults: userDefaults)
    let folderID = store.addFolder(name: "aaa")
    store.updateFolderIcon(id: folderID, to: "🚀")
    let snippetID = store.addSnippet(to: folderID)
    store.updateSnippet(id: snippetID, in: folderID, name: "bbb", content: "cdef")

    let result = try XCTUnwrap(store.searchResults(for: "aaa bbb").first?.object)
    XCTAssertEqual(result.snippetFolderIcon, "🚀")
    XCTAssertEqual(result.snippetAccessoryText, "🚀")
    XCTAssertNil(result.snippetAccessoryImage)
  }

  func testStoreSearchResultsUseDefaultFolderIconForSnippetRows() throws {
    let suiteName = "org.p0deje.Maccy.SnippetStoreTests.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }

    let store = SnippetsStore(userDefaults: userDefaults)
    let folderID = store.addFolder(name: "aaa")
    let snippetID = store.addSnippet(to: folderID)
    store.updateSnippet(id: snippetID, in: folderID, name: "bbb", content: "cdef")

    let result = try XCTUnwrap(store.searchResults(for: "aaa bbb").first?.object)
    XCTAssertNil(result.snippetFolderIcon)
    XCTAssertNotNil(result.snippetAccessoryImage)
  }
}
