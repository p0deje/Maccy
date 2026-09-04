import SwiftData
import XCTest
@testable import Maccy

@MainActor
final class SnippetsTests: XCTestCase {
  private let context = Storage.shared.context
  private var snippets: Snippets!

  override func setUpWithError() throws {
    try context.fetch(FetchDescriptor<Snippet>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<SnippetFolder>()).forEach(context.delete)
    context.processPendingChanges()
    try context.save()
    snippets = Snippets()
  }

  func testLoadsFoldersAndSnippetsInOrder() throws {
    let second = SnippetFolder(name: "Second", order: 1)
    let first = SnippetFolder(name: "First", order: 0)
    context.insert(second)
    context.insert(first)
    context.insert(Snippet(name: "B", content: "second", order: 1, folder: first))
    context.insert(Snippet(name: "A", content: "first", order: 0, folder: first))
    try context.save()

    snippets.reload()
    XCTAssertEqual(snippets.visibleRows.map(\.name), ["First", "Second"])

    snippets.selectedID = first.id
    snippets.activate(flags: [])
    XCTAssertEqual(snippets.visibleRows.map(\.name), ["A", "B"])
  }

  func testSearchesNamesContentAndFolderNames() throws {
    let folder = SnippetFolder(name: "Deploy", order: 0)
    context.insert(folder)
    context.insert(Snippet(name: "Restart", content: "kubectl rollout restart", folder: folder))
    try context.save()
    snippets.reload()

    snippets.searchQuery = "kubectl"
    XCTAssertEqual(snippets.visibleRows.map(\.name), ["Restart"])
    snippets.searchQuery = "deploy"
    XCTAssertEqual(snippets.visibleRows.map(\.name), ["Restart"])
  }

  func testDeletingFolderCascadesToSnippets() throws {
    let folder = SnippetFolder(name: "Folder")
    context.insert(folder)
    context.insert(Snippet(name: "Snippet", folder: folder))
    try context.save()

    context.delete(folder)
    try context.save()

    XCTAssertEqual(try context.fetchCount(FetchDescriptor<SnippetFolder>()), 0)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<Snippet>()), 0)
  }

  func testNavigationWrapsAndReturnsToFolders() throws {
    let first = SnippetFolder(name: "First", order: 0)
    let second = SnippetFolder(name: "Second", order: 1)
    context.insert(first)
    context.insert(second)
    try context.save()
    snippets.reload()

    snippets.highlightFirst()
    snippets.highlightPrevious()
    XCTAssertEqual(snippets.selectedID, second.id)
    snippets.highlightNext()
    XCTAssertEqual(snippets.selectedID, first.id)
    snippets.activate(flags: [])
    XCTAssertTrue(snippets.goBack())
    XCTAssertNil(snippets.currentFolder)
  }

  func testSelectingShortcutAndOpeningFolder() throws {
    let first = SnippetFolder(name: "First", order: 0)
    let second = SnippetFolder(name: "Second", order: 1)
    context.insert(first)
    context.insert(second)
    try context.save()
    snippets.reload()

    snippets.selectShortcut(at: 1)
    XCTAssertEqual(snippets.selectedID, second.id)
    XCTAssertTrue(snippets.openSelectedFolder())
    XCTAssertEqual(snippets.currentFolder?.id, second.id)
  }
}
